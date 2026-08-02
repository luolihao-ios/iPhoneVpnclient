#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>

#include <memory>

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
  static constexpr UINT kTrayMessage = WM_APP + 1;
  static constexpr UINT kTrayShowCommand = 1001;
  static constexpr UINT kTrayExitCommand = 1002;

  void InitializeTray();
  void RemoveTray();
  void ShowFromTray();
  void HideToTray();
  void ExitFromTray();
  void ShowTrayMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  NOTIFYICONDATAW tray_icon_{};
  bool tray_initialized_ = false;
  bool quitting_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
