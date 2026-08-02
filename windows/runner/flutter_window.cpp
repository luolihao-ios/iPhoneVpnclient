#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  InitializeTray();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTray();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::InitializeTray() {
  if (tray_initialized_) return;
  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = LoadIconW(GetModuleHandle(nullptr),
                               MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Forge VPN");
  tray_initialized_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
}

void FlutterWindow::RemoveTray() {
  if (!tray_initialized_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_initialized_ = false;
}

void FlutterWindow::ShowFromTray() {
  Show();
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::HideToTray() {
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::ExitFromTray() {
  quitting_ = true;
  RemoveTray();
  SetQuitOnClose(true);
  Destroy();
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kTrayShowCommand, L"显示 Forge VPN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"退出");

  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                                      point.x, point.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  if (command == kTrayShowCommand) ShowFromTray();
  if (command == kTrayExitCommand) ExitFromTray();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Intercept close and tray messages before Flutter sees them so closing the
  // native window always becomes a tray hide operation.
  if (message == WM_CLOSE) {
    if (!quitting_) {
      HideToTray();
      return 0;
    }
  }
  if (message == kTrayMessage) {
    if (lparam == WM_LBUTTONDBLCLK) {
      ShowFromTray();
      return 0;
    }
    if (lparam == WM_RBUTTONUP) {
      ShowTrayMenu();
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_COMMAND:
      if (LOWORD(wparam) == kTrayShowCommand) {
        ShowFromTray();
        return 0;
      }
      if (LOWORD(wparam) == kTrayExitCommand) {
        ExitFromTray();
        return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
