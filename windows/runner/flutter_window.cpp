#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <string>
#include <cwchar>
#include <cstdlib>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

bool ReadRegistryString(const wchar_t* name, std::wstring* value) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_READ,
                    &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buffer[2048]{};
  DWORD size = sizeof(buffer);
  const auto result = RegQueryValueExW(key, name, nullptr, nullptr,
                                       reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  if (result != ERROR_SUCCESS) return false;
  *value = buffer;
  return true;
}

bool ReadRegistryDword(const wchar_t* name, DWORD* value) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_READ,
                    &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD size = sizeof(*value);
  const auto result = RegQueryValueExW(key, name, nullptr, nullptr,
                                       reinterpret_cast<LPBYTE>(value), &size);
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

void DeleteRegistryValue(const wchar_t* name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_SET_VALUE,
                    &key) == ERROR_SUCCESS) {
    RegDeleteValueW(key, name);
    RegCloseKey(key);
  }
}

void NotifyProxySettingsChanged() {
  SendMessageTimeoutW(
      HWND_BROADCAST, WM_SETTINGCHANGE, 0,
      reinterpret_cast<LPARAM>(L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"),
      SMTO_ABORTIFHUNG, 1000, nullptr);
}

void RestoreForgeProxySync() {
  std::wstring marker;
  if (!ReadRegistryString(L"ForgeVPNProxyOwned", &marker) || marker != L"1") {
    DWORD enabled = 0;
    std::wstring server;
    if (ReadRegistryDword(L"ProxyEnable", &enabled) &&
        ReadRegistryString(L"ProxyServer", &server) && enabled == 1 &&
        server == L"127.0.0.1:2080") {
      HKEY key = nullptr;
      if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0,
                        KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
        const DWORD disabled = 0;
        RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                       reinterpret_cast<const BYTE*>(&disabled),
                       sizeof(disabled));
        RegDeleteValueW(key, L"ProxyServer");
        RegCloseKey(key);
      }
    }
    NotifyProxySettingsChanged();
    return;
  }
  DWORD enabled = 0;
  std::wstring server;
  if (!ReadRegistryDword(L"ProxyEnable", &enabled) ||
      !ReadRegistryString(L"ProxyServer", &server) || enabled != 1 ||
      server != L"127.0.0.1:2080") {
    NotifyProxySettingsChanged();
    return;
  }

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_SET_VALUE,
                    &key) != ERROR_SUCCESS) {
    NotifyProxySettingsChanged();
    return;
  }
  const wchar_t* names[] = {L"ProxyEnable", L"ProxyServer", L"ProxyOverride"};
  const wchar_t* backups[] = {L"ForgeVPNProxyBeforeEnable",
                              L"ForgeVPNProxyBeforeServer",
                              L"ForgeVPNProxyBeforeOverride"};
  for (int i = 0; i < 3; ++i) {
    std::wstring value;
    if (ReadRegistryString(backups[i], &value)) {
      if (i == 0) {
        const DWORD previous = std::wcstoul(value.c_str(), nullptr, 10);
        RegSetValueExW(key, names[i], 0, REG_DWORD,
                       reinterpret_cast<const BYTE*>(&previous),
                       sizeof(previous));
      } else {
        RegSetValueExW(key, names[i], 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(value.c_str()),
                       static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
      }
    } else {
      RegDeleteValueW(key, names[i]);
    }
    RegDeleteValueW(key, backups[i]);
  }
  RegDeleteValueW(key, L"ForgeVPNProxyOwned");
  RegCloseKey(key);
  NotifyProxySettingsChanged();
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  // Clear stale Forge VPN proxy ownership left by an interrupted shutdown or reboot.
  RestoreForgeProxySync();
  if (!Win32Window::OnCreate()) return false;

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { Show(); });
  flutter_controller_->ForceRedraw();
  InitializeTray();
  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTray();
  flutter_controller_ = nullptr;
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

void FlutterWindow::HideToTray() { ShowWindow(GetHandle(), SW_HIDE); }

void FlutterWindow::ExitFromTray() {
  quitting_ = true;
  RestoreForgeProxySync();
  RemoveTray();
  SetQuitOnClose(true);
  Destroy();
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kTrayShowCommand, L"Show Forge VPN");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"Exit");

  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                                      point.x, point.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  if (command == kTrayShowCommand) ShowFromTray();
  if (command == kTrayExitCommand) ExitFromTray();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && !quitting_) {
    HideToTray();
    return 0;
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

  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(
        hwnd, message, wparam, lparam);
    if (result) return *result;
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
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
