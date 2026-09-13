#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "kiosk_bridge.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Real 'app.olive/kiosk' + 'app.olive/kiosk_events' channel implementation
  // (MASTERFILE Sec.5.20, Sec.8.3). Constructed once GetHandle() is valid and
  // destroyed before the window itself so its destructor can still restore
  // window state -- see kiosk_bridge.h.
  std::unique_ptr<KioskBridge> kiosk_bridge_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
