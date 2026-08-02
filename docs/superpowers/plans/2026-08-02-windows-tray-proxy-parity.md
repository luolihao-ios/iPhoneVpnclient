# Windows 托盘与代理分流一致性实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 在现有 sing-box CLI Windows 实现上补齐系统代理全局/智能分流、托盘生命周期和桌面导航清理。

**架构：** Dart 侧新增可注入的 Windows 注册表代理服务，由 `AppProvider` 在核心连接状态边界启停；Windows runner 原生处理 WM_CLOSE 和托盘菜单；Flutter 继续复用现有配置生成器与桌面布局。

**技术栈：** Flutter/Dart、`dart:io`、Windows 注册表命令 `reg.exe`、Win32 Shell_NotifyIcon、现有 sing-box CLI。

## 全局约束

- 全局代理和智能分流使用 `127.0.0.1:2080`，不启用 Windows TUN。
- 系统代理只在核心确认启动成功后写入，断开/异常/退出时条件恢复。
- UI 文案继续使用现有中文本地化资源，Windows 使用 NavigationRail + AppBar。
- 不新增 Flutter tray 或代理插件。

### 任务 1：Windows 系统代理服务

**文件：**
- 创建：`lib/services/windows_proxy_service.dart`
- 创建：`test/windows_proxy_service_test.dart`

**接口：**
- `WindowsProxyService({RegistryAdapter? registry})`
- `Future<void> enable({required String proxyServer})`
- `Future<void> restore()`
- `bool get ownsCurrentSettings`

- [ ] 先写测试：验证启用保存 `ProxyEnable/ProxyServer/ProxyOverride`，恢复原值；验证用户改动后不覆盖；验证注册表失败抛出可诊断异常。
- [ ] 运行 `flutter test test/windows_proxy_service_test.dart`，确认测试因服务不存在而失败。
- [ ] 实现 `RegistryAdapter` 的异步 `reg query/add/delete` 封装，保存快照并仅在当前值仍等于 Forge 写入值时恢复。
- [ ] 再运行同一测试文件，确认通过。

### 任务 2：Provider 连接生命周期接入

**文件：**
- 修改：`lib/providers/app_provider.dart`
- 修改：`test/app_provider_test.dart`（若不存在则创建）

**接口：**
- Windows 连接成功后调用 `WindowsProxyService.enable(proxyServer: '127.0.0.1:2080')`。
- Windows 断开、核心退出和 `dispose` 调用 `restore()`。

- [ ] 先添加测试：核心连接回调为 true 时启用代理；回调为 false 时恢复代理；启动失败不写代理。
- [ ] 运行对应测试确认红灯。
- [ ] 注入代理服务，修改 `_initDesktop`、`disconnect`、异常退出回调和 `dispose`，让 `routeMode` 继续传给现有 sing-box 配置。
- [ ] 运行 Provider 测试和已有诊断/核心测试，确认通过。

### 任务 3：移除重复品牌块

**文件：**
- 修改：`lib/main.dart`
- 修改/创建：`test/main_navigation_test.dart`

- [ ] 添加桌面导航测试，确认顶部存在一个 Forge VPN 品牌，NavigationRail 不再渲染第二个品牌块。
- [ ] 运行测试确认当前实现失败。
- [ ] 删除 `_buildNavRail` 的 `leading`，保留 AppBar 品牌和三个中文导航项。
- [ ] 运行导航测试确认通过。

### 任务 4：Win32 托盘生命周期

**文件：**
- 修改：`windows/runner/flutter_window.h`
- 修改：`windows/runner/flutter_window.cpp`
- 修改：`windows/runner/main.cpp`
- 修改：`windows/runner/CMakeLists.txt`

- [ ] 在 `FlutterWindow` 增加托盘初始化/移除、显示、隐藏、退出状态和 `WM_APP` 通知处理。
- [ ] `WM_CLOSE` 隐藏窗口并保留消息循环；托盘双击显示并激活；托盘菜单“显示 Forge VPN/退出”。
- [ ] 退出时先移除托盘图标，再设置 `SetQuitOnClose(true)` 销毁窗口，让 Dart 生命周期执行恢复逻辑。
- [ ] 将 `main.cpp` 的初始关闭策略改为托盘模式，并把新源文件加入 CMake（若实现放在现有文件则不增加源文件）。
- [ ] 由用户在 VS 开发者命令行运行 `flutter build windows`，人工验证关闭、恢复和退出。

### 任务 5：验证与文档

**文件：**
- 修改：`docs/superpowers/specs/2026-08-02-windows-tray-proxy-parity-design.md`（仅在实现细节变化时）

- [ ] 运行 `flutter test test/windows_proxy_service_test.dart test/singbox_service_test.dart test/desktop_vpn_diagnostics_test.dart test/windows_vpn_diagnostics_test.dart`。
- [ ] 运行 `flutter analyze lib/services/windows_proxy_service.dart lib/providers/app_provider.dart lib/main.dart`。
- [ ] 将上述命令发给用户执行；记录 Windows 构建和托盘人工验证结果。
