#include "kiosk_bridge.h"

#include <flutter/standard_method_codec.h>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EventChannel;
using flutter::EventSink;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;
using flutter::StandardMethodCodec;
using flutter::StreamHandlerError;
using flutter::StreamHandlerFunctions;

namespace {
// Arbitrary, just needs to be unique within this HWND's timer namespace.
constexpr UINT_PTR kHeartbeatTimerId = 0xB4A17C;
constexpr UINT kHeartbeatIntervalMs = 3000;
}  // namespace

KioskBridge* KioskBridge::active_instance_ = nullptr;

KioskBridge::KioskBridge(HWND window_handle) : window_handle_(window_handle) {}

KioskBridge::~KioskBridge() {
  // Defensive: guarantees the hook and timer never outlive this object even
  // if stopLockTask was never called (e.g. the app is closed while locked).
  Stop();
}

void KioskBridge::RegisterWith(flutter::BinaryMessenger* messenger) {
  method_channel_ = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, kMethodChannel, &StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == kMStart) {
          Start();
          result->Success(EncodableValue(CurrentMode()));
        } else if (method == kMStop) {
          Stop();
          result->Success();
        } else if (method == kMMode) {
          result->Success(EncodableValue(CurrentMode()));
        } else if (method == kMIsOwner) {
          // Never true on Windows -- see the class doc.
          result->Success(EncodableValue(false));
        } else {
          result->NotImplemented();
        }
      });

  event_channel_ = std::make_unique<EventChannel<EncodableValue>>(
      messenger, kEventChannel, &StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* /* arguments */,
                 std::unique_ptr<EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<StreamHandlerError<EncodableValue>> {
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue* /* arguments */)
              -> std::unique_ptr<StreamHandlerError<EncodableValue>> {
            event_sink_ = nullptr;
            return nullptr;
          }));
}

void KioskBridge::HandleWindowMessage(UINT message, WPARAM wparam,
                                       LPARAM /* lparam */) {
  switch (message) {
    case WM_ACTIVATE:
      SetForeground(LOWORD(wparam) != WA_INACTIVE);
      break;
    case WM_NCACTIVATE:
      // wparam is a BOOL here, not the WA_* codes WM_ACTIVATE uses. Both
      // messages can fire for the same transition; SetForeground() dedupes
      // on actual state change so this never double-emits.
      SetForeground(wparam != FALSE);
      break;
    case WM_SIZE:
      // Only meaningful while lock mode is supposed to be active: Stop()
      // always flips locked_ to false before it touches the window, so its
      // own restore never reaches here as a false "exit".
      if (locked_ && (wparam == SIZE_RESTORED || wparam == SIZE_MINIMIZED)) {
        EmitExited();
      }
      break;
    case WM_TIMER:
      if (wparam == kHeartbeatTimerId && locked_) {
        HeartbeatCheckHook();
      }
      break;
    default:
      break;
  }
}

void KioskBridge::Start() {
  if (locked_) return;
  locked_ = true;

  saved_style_ = GetWindowLongPtr(window_handle_, GWL_STYLE);
  saved_ex_style_ = GetWindowLongPtr(window_handle_, GWL_EXSTYLE);
  saved_placement_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(window_handle_, &saved_placement_);

  // Best-effort borderless fullscreen: drop the caption/frame/system menu so
  // there is no visible close/minimize/restore control, then cover the
  // monitor. See the class doc -- this is cooperative, not enforced.
  LONG_PTR style = saved_style_;
  style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
             WS_SYSMENU);
  SetWindowLongPtr(window_handle_, GWL_STYLE, style);

  HMONITOR monitor =
      MonitorFromWindow(window_handle_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const RECT& r = monitor_info.rcMonitor;
    SetWindowPos(window_handle_, HWND_TOP, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  ShowWindow(window_handle_, SW_MAXIMIZE);

  InstallKeyboardHook();
  SetTimer(window_handle_, kHeartbeatTimerId, kHeartbeatIntervalMs, nullptr);
}

void KioskBridge::Stop() {
  if (!locked_) return;
  locked_ = false;

  KillTimer(window_handle_, kHeartbeatTimerId);
  RemoveKeyboardHook();

  SetWindowLongPtr(window_handle_, GWL_STYLE, saved_style_);
  SetWindowLongPtr(window_handle_, GWL_EXSTYLE, saved_ex_style_);
  SetWindowPlacement(window_handle_, &saved_placement_);
  SetWindowPos(window_handle_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

// Always "assigned", never "locked" -- Windows has nothing this bridge could
// point to that would make "locked" true. See the class doc.
std::string KioskBridge::CurrentMode() { return "assigned"; }

void KioskBridge::InstallKeyboardHook() {
  if (keyboard_hook_) return;
  active_instance_ = this;
  keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, &KioskBridge::LowLevelKeyboardProc,
                                     GetModuleHandle(nullptr), 0);
}

void KioskBridge::RemoveKeyboardHook() {
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  if (active_instance_ == this) {
    active_instance_ = nullptr;
  }
}

void KioskBridge::HeartbeatCheckHook() {
  if (!keyboard_hook_) {
    // Never successfully installed (e.g. SetWindowsHookEx failed) -- retry.
    InstallKeyboardHook();
    return;
  }
  // See the class doc: Windows gives no notification when it silently drops
  // a slow low-level hook. Cycling it here is both the mitigation
  // (guarantees a fresh, presumably-fast hook is in place) and the only
  // available detector: if the OS had already dropped `previous`, this
  // Unhook call returns FALSE, which is our signal that Alt+Tab / the
  // Windows key / Ctrl+Esc were live for some window before we noticed.
  const HHOOK previous = keyboard_hook_;
  keyboard_hook_ = nullptr;
  const BOOL was_still_installed = UnhookWindowsHookEx(previous);
  if (!was_still_installed) {
    EmitExited();
  }
  InstallKeyboardHook();
}

LRESULT CALLBACK KioskBridge::LowLevelKeyboardProc(int code, WPARAM wparam,
                                                    LPARAM lparam) {
  if (code == HC_ACTION && active_instance_ && active_instance_->locked_) {
    const auto* kb = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    const bool key_down = (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN);
    const bool win_key = kb->vkCode == VK_LWIN || kb->vkCode == VK_RWIN;
    const bool alt_tab = kb->vkCode == VK_TAB && (kb->flags & LLKHF_ALTDOWN);
    const bool ctrl_esc =
        kb->vkCode == VK_ESCAPE && (GetAsyncKeyState(VK_CONTROL) & 0x8000);

    // Swallow the Windows key on both down and up (a keyup alone can still
    // surface the Start menu for a bare tap), and swallow Alt+Tab / Ctrl+Esc
    // on keydown. Deliberately NOT touching Ctrl+Alt+Del: that combination
    // is the OS-reserved secure attention sequence and is not delivered to
    // user-mode hooks at all -- there is nothing here to block even if we
    // wanted to, and the class doc says so plainly rather than implying
    // otherwise by omission.
    if (win_key || (key_down && (alt_tab || ctrl_esc))) {
      return 1;
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void KioskBridge::SetForeground(bool active) {
  if (active == foreground_) return;
  foreground_ = active;
  if (active) {
    EmitResumed();
  } else {
    EmitBackgrounded();
  }
}

void KioskBridge::EmitExited() {
  EncodableMap map;
  map[EncodableValue("event")] = EncodableValue(std::string(kEExited));
  map[EncodableValue("mode")] = EncodableValue(CurrentMode());
  if (event_sink_) event_sink_->Success(EncodableValue(map));
}

void KioskBridge::EmitBackgrounded() { EmitEvent(kEBackground); }

void KioskBridge::EmitResumed() { EmitEvent(kEResumed); }

void KioskBridge::EmitEvent(const std::string& name) {
  if (!event_sink_) return;
  EncodableMap map;
  map[EncodableValue("event")] = EncodableValue(name);
  event_sink_->Success(EncodableValue(map));
}
