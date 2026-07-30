# Windows 运行状态与内容对齐实施计划

> **面向执行代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施本计划。步骤使用复选框（`- [ ]`）跟踪。

**Goal:** 在不改变 Windows sing-box 命令行架构的前提下，补齐可信运行状态、诊断与日志，并逐项核查移动端已交付内容在 Windows 桌面布局中的可用性。

**Architecture:** `SingBoxController` 是 Windows sing-box 进程及其运行快照的唯一所有者，启动成功须经过短暂存活确认。独立的桌面诊断模块读取该快照、文件和本机端口；`AppProvider` 将其暴露给日志页。界面共享内容保持一致，但使用既有 NavigationRail、指标行和节点表格呈现桌面体验。

**Tech Stack:** Flutter、Dart、Provider、`dart:io`、`flutter_test`、sing-box CLI。

## 全局约束

- 不增加 Windows 原生 TUN、libbox 或 `MethodChannel`。
- 不修改当前未提交的 Android 文件。
- Windows 不接管外部遗留的 `sing-box.exe`。
- 共享功能在 Windows 提供同等入口、数据与反馈；布局遵循桌面多栏、表格和鼠标/键盘交互习惯。
- 所有新增用户可见文本使用现有中英文本地化资源；日志中的技术字段保持原样。

---

## 文件结构

- 修改：`lib/services/singbox_service.dart` — 维护 sing-box 生命周期和可读取的桌面运行快照。
- 新建：`lib/core/desktop_vpn_diagnostics.dart` — 根据快照检查核心文件、配置和端口，并返回稳定的键值诊断结果。
- 修改：`lib/providers/app_provider.dart` — 初始化、连接和退出时使用真实进程状态，并向界面提供 Windows 诊断。
- 修改：`lib/screens/logs_screen.dart` — 按平台调用 Android、iOS 或 Windows 诊断，结果写入现有日志。
- 修改：`lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb` — 增加桌面诊断与状态说明的固定界面文字；重新生成本地化文件。
- 修改：`PROJECT_SUMMARY.md` — 记录移动端功能与 Windows 桌面呈现的对照结论。
- 新建：`test/singbox_service_test.dart` — 覆盖控制器启动与退出状态。
- 新建：`test/desktop_vpn_diagnostics_test.dart` — 覆盖诊断字段与端口检查。
- 新建：`test/logs_screen_test.dart` — 覆盖 Windows 诊断入口及结果写入日志。

### Task 1: 实现可验证的桌面进程运行快照

**Files:**
- Modify: `lib/services/singbox_service.dart`
- Test: `test/singbox_service_test.dart`

**Interfaces:**
- Produces: `SingBoxRuntimeSnapshot({required bool running, int? pid, DateTime? startedAt, String? configPath, int? exitCode, List<String> recentLogs})`。
- Produces: `SingBoxController.snapshot`、`Future<Map<String, dynamic>> connect(...)` 和现有 `disconnect()`。
- Consumes: `OnSingBoxState`，其 `connected` 为 `true` 仅代表通过存活确认的进程。

- [ ] **Step 1: 写出失败的控制器状态测试**

```dart
test('控制器仅在启动窗口后仍存活时报告已连接', () async {
  final controller = SingBoxController(
    corePath: core.path,
    runtimeDir: temp.path,
    startupGracePeriod: Duration.zero,
  );

  await controller.connect(node: node);

  expect(controller.snapshot.running, isTrue);
  expect(controller.snapshot.pid, isNotNull);
  expect(controller.snapshot.startedAt, isNotNull);
});

test('活动进程退出后保存退出码并报告断开', () async {
  final controller = SingBoxController(
    corePath: immediateExitCore.path,
    runtimeDir: temp.path,
    startupGracePeriod: const Duration(milliseconds: 20),
  );

  await expectLater(controller.connect(node: node), throwsA(isA<Exception>()));
  expect(controller.snapshot.running, isFalse);
  expect(controller.snapshot.exitCode, isNotNull);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/singbox_service_test.dart`

Expected: FAIL，因为 `SingBoxRuntimeSnapshot`、`snapshot` 和 `startupGracePeriod` 尚不存在。

- [ ] **Step 3: 实现最小运行快照与启动确认**

```dart
class SingBoxRuntimeSnapshot {
  const SingBoxRuntimeSnapshot({
    required this.running,
    this.pid,
    this.startedAt,
    this.configPath,
    this.exitCode,
    this.recentLogs = const [],
  });

  final bool running;
  final int? pid;
  final DateTime? startedAt;
  final String? configPath;
  final int? exitCode;
  final List<String> recentLogs;
}
```

在 `connect` 内部于 `Process.start` 后保存 PID、启动时间和配置路径；等待 `startupGracePeriod` 后检查当前运行编号与 `_process` 是否仍存在。已退出则抛出包含退出码的异常，不调用 `onState(connected: true)`。stdout/stderr 每写入一行，同时写入最多 120 行的 `recentLogs`；`exitCode` 回调更新快照并对活动运行调用 `onState(connected: false, code: code)`。

- [ ] **Step 4: 运行控制器测试并确认通过**

Run: `flutter test test/singbox_service_test.dart`

Expected: PASS，成功进程生成运行快照；立即退出进程不进入已连接状态且保留退出码。

- [ ] **Step 5: 提交任务改动**

```bash
git add lib/services/singbox_service.dart test/singbox_service_test.dart
git commit -m "feat: track Windows sing-box runtime state"
```

### Task 2: 实现独立的 Windows 诊断

**Files:**
- Create: `lib/core/desktop_vpn_diagnostics.dart`
- Test: `test/desktop_vpn_diagnostics_test.dart`

**Interfaces:**
- Consumes: `SingBoxRuntimeSnapshot`、`corePath` 和默认端口 `defaultHttpPort`、`defaultSocksPort`、`defaultApiPort`。
- Produces: `Future<Map<String, dynamic>> collectDesktopVpnDiagnostics({required String corePath, required SingBoxRuntimeSnapshot snapshot, Future<bool> Function(int port)? isPortListening})`。

- [ ] **Step 1: 写出失败的桌面诊断测试**

```dart
test('诊断报告核心、配置、运行状态和端口', () async {
  final result = await collectDesktopVpnDiagnostics(
    corePath: core.path,
    snapshot: SingBoxRuntimeSnapshot(
      running: true,
      pid: 4242,
      startedAt: DateTime.utc(2026, 7, 30),
      configPath: config.path,
      recentLogs: const ['INFO started'],
    ),
    isPortListening: (port) async => port == defaultHttpPort,
  );

  expect(result['coreExists'], isTrue);
  expect(result['configExists'], isTrue);
  expect(result['running'], isTrue);
  expect(result['httpPortListening'], isTrue);
  expect(result['socksPortListening'], isFalse);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/desktop_vpn_diagnostics_test.dart`

Expected: FAIL，因为 `collectDesktopVpnDiagnostics` 尚不存在。

- [ ] **Step 3: 实现最小桌面诊断模块**

```dart
Future<bool> isTcpPortListening(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 250),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}
```

返回包含 `platform`、`corePath`、`coreExists`、`running`、`pid`、`startedAt`、`configPath`、`configExists`、`httpPortListening`、`socksPortListening`、`apiPortListening`、`exitCode` 和 `recentLogs` 的 `Map<String, dynamic>`。配置路径为空时 `configExists` 为 `false`；日志数组最多返回最后 20 行。

- [ ] **Step 4: 运行诊断测试并确认通过**

Run: `flutter test test/desktop_vpn_diagnostics_test.dart`

Expected: PASS，端口测试替身决定对应端口字段，文件与快照字段准确保留。

- [ ] **Step 5: 提交任务改动**

```bash
git add lib/core/desktop_vpn_diagnostics.dart test/desktop_vpn_diagnostics_test.dart
git commit -m "feat: add Windows VPN diagnostics"
```

### Task 3: 接入 Provider、日志页与本地化

**Files:**
- Modify: `lib/providers/app_provider.dart`
- Modify: `lib/screens/logs_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_localizations.dart`
- Modify: `lib/l10n/app_localizations_en.dart`
- Modify: `lib/l10n/app_localizations_zh.dart`
- Test: `test/logs_screen_test.dart`

**Interfaces:**
- Consumes: `SingBoxController.snapshot` 和 `collectDesktopVpnDiagnostics(...)`。
- Produces: `AppProvider.diagnoseVpn()`，返回 `Future<Map<String, dynamic>>`；Logs 页只调用该平台无关接口。

- [ ] **Step 1: 写出失败的日志页 Windows 分派测试**

```dart
testWidgets('Windows 检查 VPN 将桌面诊断写入日志', (tester) async {
  final provider = AppProvider.forTesting(
    platform: TargetPlatform.windows,
    desktopDiagnostics: () async => {'platform': 'windows', 'running': false},
  );

  await tester.pumpWidget(testApp(provider: provider, child: const LogsScreen()));
  await tester.tap(find.text('检查 VPN'));
  await tester.pumpAndSettle();

  expect(provider.runtime.logs, contains('[diag] platform: windows'));
  expect(provider.runtime.logs, contains('[diag] running: false'));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/logs_screen_test.dart`

Expected: FAIL，因为 `AppProvider.diagnoseVpn` 和 `AppProvider.forTesting` 尚不存在，日志页仍直接分派 Android/iOS 服务。

- [ ] **Step 3: 实现 Provider 诊断入口和页面调用**

```dart
Future<Map<String, dynamic>> diagnoseVpn() async {
  if (_isAndroid) return AndroidVpnService().diagnose();
  if (_isiOS) return IosVpnService().diagnose();
  if (_controller == null) return {'platform': 'windows', 'error': 'controller unavailable'};
  return collectDesktopVpnDiagnostics(
    corePath: _controller!.corePath,
    snapshot: _controller!.snapshot,
  );
}
```

在 `_initDesktop` 的状态回调中，连接状态完全以控制器回调为准；删除 `_connectDesktop` 内提前写入 `connected: true` 的逻辑，且仅在控制器连接成功后启动流量定时器。日志页按钮调用 `provider.diagnoseVpn()`，将结果逐条写成 `[diag] key: value`。为诊断进行中、桌面运行状态和控制器不可用补充中英文 ARB 字符串，并执行 `flutter gen-l10n` 更新生成文件。

- [ ] **Step 4: 运行日志页和现有移动端服务测试**

Run: `flutter test test/logs_screen_test.dart test/android_vpn_service_test.dart test/ios_vpn_service_test.dart`

Expected: PASS，Windows 走 Provider 桌面分支，Android/iOS 仍保留各自诊断路径。

- [ ] **Step 5: 提交任务改动**

```bash
git add lib/providers/app_provider.dart lib/screens/logs_screen.dart lib/l10n test/logs_screen_test.dart
git commit -m "feat: expose Windows diagnostics in logs"
```

### Task 4: 完成移动端内容与 Windows 桌面呈现审计

**Files:**
- Modify: `PROJECT_SUMMARY.md`
- Test: `test/dashboard_responsive_test.dart`
- Test: `test/main_navigation_test.dart`
- Test: `test/subscription_import_card_test.dart`
- Test: `test/log_export_test.dart`

**Interfaces:**
- Consumes: 现有 `DashboardScreen`、`MainShell`、`SubscriptionImportCard`、`LogsScreen` 和 `AppProvider.diagnoseVpn()`。
- Produces: 一份文档化的对照结论，确认 Windows 在 NavigationRail、Dashboard 桌面节点表格、订阅导入、路由模式、日志导出与诊断入口中提供一致内容。

- [ ] **Step 1: 为 Windows 桌面关键内容补充失败的 widget 断言**

```dart
testWidgets('Windows 宽屏显示桌面导航和订阅节点内容', (tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  await tester.pumpWidget(const ForgeVpnApp());
  await tester.pumpAndSettle();

  expect(find.byType(NavigationRail), findsOneWidget);
  expect(find.text('Subscription Servers'), findsOneWidget);
  expect(find.text('Import Subscription'), findsOneWidget);
});
```

- [ ] **Step 2: 运行桌面内容测试并确认失败**

Run: `flutter test test/dashboard_responsive_test.dart test/main_navigation_test.dart test/subscription_import_card_test.dart`

Expected: PASS，既有宽屏布局已使用 `NavigationRail`、订阅导入卡和桌面节点表格；若断言失败，仅调整 Windows 桌面呈现所缺失的内容，不改变手机布局。

- [ ] **Step 3: 以最小界面改动完成 Windows 内容对齐**

保持 `MainShell` 的 `NavigationRail`、Dashboard 的 `_TableNodeList` 和常驻连接卡布局；仅在上述断言失败时补充缺失的 Windows 可见内容、本地化文本、诊断状态展示或语义标签。不要把手机卡片布局复制到宽屏，不新增移动端专属的权限或 TUN 控件。

- [ ] **Step 4: 运行完整相关回归与静态检查**

Run: `dart format --set-exit-if-changed lib test && flutter test && flutter analyze`

Expected: PASS，所有 Dart 文件已格式化；全部测试与分析无错误。

- [ ] **Step 5: 更新项目摘要并提交任务改动**

在 `PROJECT_SUMMARY.md` 新增“Windows 内容对齐”小节，列出已核查的共享功能、Windows 命令行诊断补齐项与保留的移动端原生专属项。

```bash
git add PROJECT_SUMMARY.md test/dashboard_responsive_test.dart test/main_navigation_test.dart test/subscription_import_card_test.dart test/log_export_test.dart
git commit -m "docs: record Windows mobile parity audit"
```
