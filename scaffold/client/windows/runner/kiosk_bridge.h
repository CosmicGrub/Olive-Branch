#ifndef RUNNER_KIOSK_BRIDGE_H_
#define RUNNER_KIOSK_BRIDGE_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

// OLIVE BRANCH -- Windows kiosk bridge. MASTERFILE Sec.5.20, Sec.8.3.
//
// UNVERIFIED: this is a real implementation (not a contract stub like the
// former native/windows/AssignedAccessBridge.cs it replaces), and it does
// compile cleanly in isolation -- `cl /c /W4` against the actual cached
// Flutter Windows embedder headers (cpp_client_wrapper) reports zero errors
// and zero warnings for both this file and the updated flutter_window.cpp.
// But that is a direct compiler invocation outside the real build graph, not
// a real build: `flutter build windows` in this environment fails before
// CMake even configures --
//   "Unable to find suitable Visual Studio toolchain."
// -- because the local Visual Studio Build Tools 2022 install is missing the
// "Desktop development with C++" workload (`vswhere -requires
// Microsoft.VisualStudio.Workload.NativeDesktop` finds no matching
// instance; the install also reports isComplete: false). So this bridge has
// never been through the actual CMake/MSBuild link step, never produced a
// runner.exe, and never run against a real Win32 message loop. Mirrors
// MainActivity.kt/KioskBridge.kt on Android in spirit only -- Android's
// equivalent file dropped this marker because it was actually built,
// installed, and manually verified on a device; this one keeps it because
// none of that has happened here yet. See CHANGELOG.
//
// Structurally, this mirrors the split between MainActivity.kt and
// KioskBridge.kt on Android: FlutterWindow (the WndProc owner) forwards the
// handful of window messages this bridge cares about (WM_ACTIVATE /
// WM_NCACTIVATE / WM_SIZE / WM_TIMER); all the actual kiosk logic lives
// here.
//
// Windows has no device-owner-equivalent lock an app can grant itself. Real
// Assigned Access is configured OUTSIDE the app, via Settings or MDM -- an
// app cannot self-elevate into it, which is exactly why the old C# file this
// replaces was an inert contract stub in the first place. So startLockTask()
// here does the best-effort in-app measures that are genuinely achievable
// from inside a normal desktop app:
//
//   1. Best-effort borderless fullscreen: strip the caption/system menu and
//      resize to cover the monitor. A cooperative UI change, not a security
//      boundary -- Alt+F4, Task Manager, or a remote admin session can still
//      close or resize this window.
//   2. A low-level keyboard hook (WH_KEYBOARD_LL) that swallows Alt+Tab, the
//      Windows key, and Ctrl+Esc while lock mode is active. This is a real,
//      standard, legitimate Windows kiosk technique -- not a security
//      boundary either. Ctrl+Alt+Del is deliberately never touched: Windows
//      reserves that combination at the OS level (the "secure attention
//      sequence") and no user-mode hook can intercept it, by design.
//
// Per Microsoft's own documentation for WH_KEYBOARD_LL, if a low-level hook
// procedure takes too long to return, the OS silently drops it from the
// chain with **no notification** to the process that installed it. There is
// no public API to ask "is my hook still installed". The only observable
// symptom is indirect: calling UnhookWindowsHookEx on a handle the OS has
// already dropped returns FALSE. This bridge turns that into a genuine (if
// approximate) detector by re-arming the hook on a periodic heartbeat timer
// and checking that return value -- see HeartbeatCheckHook() in the .cpp.
//
// lockTaskMode() / isDeviceOwner() always report "assigned" / false. Never
// "locked" -- there is nothing on Windows this bridge could point to that
// would make that claim true, matching the honest framing the old stub
// already used and the "report defeat, don't pretend to prevent it"
// philosophy used everywhere else in this codebase (lock.ts, KioskBridge.kt).
class KioskBridge {
 public:
  // Channel names. Byte-identical to kiosk_channel.dart and (formerly)
  // AssignedAccessBridge.cs -- contract-checked by
  // packages/transport/test/transport.test.mjs.
  static constexpr char kMethodChannel[] = "app.olive/kiosk";
  static constexpr char kEventChannel[] = "app.olive/kiosk_events";

  // Method names.
  static constexpr char kMStart[] = "startLockTask";
  static constexpr char kMStop[] = "stopLockTask";
  static constexpr char kMMode[] = "lockTaskMode";
  static constexpr char kMIsOwner[] = "isDeviceOwner";

  // Event names.
  static constexpr char kEExited[] = "lockTaskExited";
  static constexpr char kEBackground[] = "backgrounded";
  static constexpr char kEResumed[] = "resumed";

  // |window_handle| is the runner's top-level HWND; it must outlive this
  // object (FlutterWindow owns both and destroys this first -- see
  // flutter_window.cpp's OnDestroy).
  explicit KioskBridge(HWND window_handle);
  ~KioskBridge();

  KioskBridge(const KioskBridge&) = delete;
  KioskBridge& operator=(const KioskBridge&) = delete;

  // Registers the method + event channels against |messenger|. Call once,
  // from FlutterWindow::OnCreate after the Flutter engine exists.
  void RegisterWith(flutter::BinaryMessenger* messenger);

  // Forwarded verbatim from FlutterWindow::MessageHandler for every message,
  // regardless of whether Flutter or the base Win32Window ends up consuming
  // it. Purely observational (backgrounded/resumed/lockTaskExited
  // bookkeeping and the hook heartbeat) -- never changes the return value of
  // the real WndProc chain.
  void HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void Start();
  void Stop();
  static std::string CurrentMode();

  void InstallKeyboardHook();
  void RemoveKeyboardHook();
  void HeartbeatCheckHook();

  void SetForeground(bool active);
  void EmitExited();
  void EmitBackgrounded();
  void EmitResumed();
  void EmitEvent(const std::string& name);

  static LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam,
                                                LPARAM lparam);

  HWND window_handle_;
  bool locked_ = false;
  bool foreground_ = true;

  // Window style/placement captured before Start() mutates them, restored
  // by Stop() so a defeat (or a plain stopLockTask call) leaves the window
  // in its normal, usable state rather than stuck borderless.
  LONG_PTR saved_style_ = 0;
  LONG_PTR saved_ex_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};

  HHOOK keyboard_hook_ = nullptr;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // WH_KEYBOARD_LL's callback is a plain function pointer (a Win32 API
  // requirement) with no user-data slot to smuggle a `this` through
  // SetWindowsHookEx, so it reaches back into whichever instance installed
  // it via this process-global. Exactly one KioskBridge exists per process
  // (one per FlutterWindow), matching this app's single-window shape.
  static KioskBridge* active_instance_;
};

#endif  // RUNNER_KIOSK_BRIDGE_H_
