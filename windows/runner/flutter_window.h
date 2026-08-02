#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
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

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  NOTIFYICONDATAW tray_icon_{};
  bool tray_initialized_ = false;
  bool quitting_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
