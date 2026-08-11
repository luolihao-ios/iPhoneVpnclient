# 首次节点快速筛查实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为启动和订阅导入增加可取消的两阶段节点筛查，在 15 秒快速窗口内尽量确认可用节点、至少寻找 5 个且总时限为 45 秒，同时保留手动全节点检查。

**Architecture:** 新建与 Flutter UI 无关的筛查调度器，负责全节点 TCP 预筛、候选排序、真实验证、时间预算和取消判断；`AppProvider` 负责把调度事件转换为节点状态并持久化。订阅下载在独立重试层处理临时网络错误，界面把现有检查按钮改为“检查/停止”双态入口。

**Tech Stack:** Dart 3、Flutter、Provider/ChangeNotifier、package:http、flutter_test、sing-box 健康检查。

## Global Constraints

- 启动恢复和导入新订阅使用快速筛查；手动“检查”仍执行全节点完整检查。
- 快速筛查先检查全部节点 TCP，再对 TCP 成功候选执行真实 sing-box 代理验证。
- 快速窗口为 15 秒，整体上限为 45 秒，最低目标为 5 个真实可用节点。
- 15 秒内不因达到 5 个而停止；15 秒后已有至少 5 个则停止领取新任务。
- 用户可随时停止自动或手动检查；已完成结果保留，未完成节点恢复“未检查”。
- 新订阅请求发起前先取消旧检查；临时网络错误最多重试 2 次。
- 不自动切换用户当前选中的节点。

---

### Task 1: 可清空的节点健康状态

**Files:**
- Modify: `lib/core/models/node.dart`
- Modify: `lib/core/node_latency.dart`
- Create: `test/node_latency_test.dart`

**Interfaces:**
- Produces: `VpnNode.copyWith({bool clearLatencyMs = false, bool clearHealthDetails = false, ...})`
- Produces: `resetNodeHealth(VpnNode node)`，返回 `HealthStatus.unknown` 且不带旧延迟/错误/目标/检查时间的节点。

- [ ] **Step 1: 编写失败测试**

```dart
test('resetNodeHealth clears stale latency and checking state', () {
  final reset = resetNodeHealth(node.copyWith(
    healthStatus: HealthStatus.checking,
    latencyMs: 88,
    healthError: 'old error',
  ));

  expect(reset.healthStatus, HealthStatus.unknown);
  expect(reset.latencyMs, isNull);
  expect(reset.healthError, isNull);
});
```

- [ ] **Step 2: 运行测试并确认红灯**

Run: `flutter test test/node_latency_test.dart`

Expected: FAIL，因为 `resetNodeHealth` 尚不存在，且当前 `copyWith(latencyMs: null)` 不能清空旧值。

- [ ] **Step 3: 实现最小状态清理接口**

```dart
VpnNode copyWith({
  // existing arguments
  bool clearLatencyMs = false,
  bool clearHealthDetails = false,
}) {
  return VpnNode(
    // existing fields
    latencyMs: clearLatencyMs ? null : latencyMs ?? this.latencyMs,
    healthError: clearHealthDetails ? null : healthError ?? this.healthError,
    healthTarget: clearHealthDetails ? null : healthTarget ?? this.healthTarget,
    latencyCheckedAt:
        clearHealthDetails ? null : latencyCheckedAt ?? this.latencyCheckedAt,
  );
}

VpnNode resetNodeHealth(VpnNode node) => node.copyWith(
      healthStatus: HealthStatus.unknown,
      clearLatencyMs: true,
      clearHealthDetails: true,
    );
```

- [ ] **Step 4: 运行测试并确认绿灯**

Run: `flutter test test/node_latency_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/core/models/node.dart lib/core/node_latency.dart test/node_latency_test.dart
git commit -m "fix: clear stale node health state"
```

### Task 2: 自适应快速筛查调度器

**Files:**
- Create: `lib/core/initial_node_screening.dart`
- Create: `test/initial_node_screening_test.dart`

**Interfaces:**
- Consumes: `VpnNode`、`HealthCheckResult`。
- Produces: `typedef NodeTcpProbe = Future<int?> Function(VpnNode node)`。
- Produces: `typedef NodeValidator = Future<HealthCheckResult> Function(VpnNode node)`。
- Produces: `Future<InitialScreeningSummary> runInitialNodeScreening({required List<VpnNode> nodes, required NodeTcpProbe tcpProbe, required NodeValidator validate, required void Function(VpnNode) onNodeChecking, required void Function(VpnNode, HealthCheckResult) onNodeResult, required bool Function() isCancelled, DateTime Function()? now, Duration quickWindow = const Duration(seconds: 15), Duration overallLimit = const Duration(seconds: 45), int minimumAvailable = 5, int tcpConcurrency = 32, int validationConcurrency = 3})`。
- Produces: `InitialScreeningSummary`，包含 TCP 检查数、真实验证数、可用数和是否被取消/到达时限。

- [ ] **Step 1: 编写全节点 TCP 预筛失败测试**

```dart
test('TCP preflight visits every node and validates only reachable nodes', () async {
  final tcpVisited = <String>[];
  final validated = <String>[];

  await runInitialNodeScreening(
    nodes: nodes,
    tcpProbe: (node) async {
      tcpVisited.add(node.id);
      return node.id == 'down' ? null : 20;
    },
    validate: (node) async {
      validated.add(node.id);
      return const HealthCheckResult(ok: true, latency: 30);
    },
    onNodeChecking: (_) {},
    onNodeResult: (_, __) {},
    isCancelled: () => false,
  );

  expect(tcpVisited.toSet(), nodes.map((node) => node.id).toSet());
  expect(validated, isNot(contains('down')));
});
```

- [ ] **Step 2: 编写时间窗口与最低数量失败测试**

```dart
test('keeps all fast results, then stops after the quick window with five',
    () async {
  final clock = FakeScreeningClock();
  final summary = await runInitialNodeScreening(
    nodes: nodes,
    now: clock.now,
    validationConcurrency: 1,
    tcpProbe: (node) async => 10,
    validate: (node) async {
      clock.advance(const Duration(seconds: 2));
      return const HealthCheckResult(ok: true, latency: 25);
    },
    onNodeChecking: (_) {},
    onNodeResult: (_, __) {},
    isCancelled: () => false,
  );

  expect(summary.availableCount, greaterThanOrEqualTo(5));
  expect(summary.validatedCount, lessThan(nodes.length));
});
```

- [ ] **Step 3: 编写取消失败测试**

```dart
test('cancellation stops new work and reports cancelled', () async {
  var cancelled = false;
  final summary = await runInitialNodeScreening(
    nodes: nodes,
    tcpProbe: (node) async => 10,
    validate: (node) async {
      cancelled = true;
      return const HealthCheckResult(ok: true, latency: 20);
    },
    onNodeChecking: (_) {},
    onNodeResult: (_, __) {},
    isCancelled: () => cancelled,
  );

  expect(summary.cancelled, isTrue);
  expect(summary.validatedCount, 1);
});
```

- [ ] **Step 4: 运行测试并确认红灯**

Run: `flutter test test/initial_node_screening_test.dart`

Expected: FAIL，因为调度器文件和接口尚不存在。

- [ ] **Step 5: 实现最小调度器**

实现要点：

```dart
const initialScreeningQuickWindow = Duration(seconds: 15);
const initialScreeningOverallLimit = Duration(seconds: 45);
const initialScreeningMinimumAvailable = 5;
const initialScreeningTcpConcurrency = 32;
const initialScreeningValidationConcurrency = 3;
```

TCP 工作者检查全部节点并收集 `(node, latency)`；候选按延迟升序排序。真实验证工作者在领取候选前检查取消状态、45 秒总时限，以及“已过 15 秒且可用数不少于 5”的停止条件。每个工作者只通过回调报告当前节点，调度器不直接依赖 `AppProvider`。

- [ ] **Step 6: 运行测试并确认绿灯**

Run: `flutter test test/initial_node_screening_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交**

```powershell
git add lib/core/initial_node_screening.dart test/initial_node_screening_test.dart
git commit -m "feat: add adaptive initial node screening"
```

### Task 3: 订阅临时网络错误重试

**Files:**
- Modify: `lib/core/subscription.dart`
- Create: `test/subscription_retry_test.dart`

**Interfaces:**
- Produces: `fetchSubscription` 在 `SocketException`、`TimeoutException` 和临时 `http.ClientException` 下最多额外请求 2 次。
- HTTP 4xx/5xx 和解析错误沿用现有错误流程，不进入网络重试。

- [ ] **Step 1: 编写失败测试**

```dart
test('retries transient request failures twice before succeeding', () async {
  final client = SequenceSubscriptionClient([
    const SocketException('The semaphore timeout period has expired'),
    const SocketException('Connection reset'),
    validSubscriptionResponse,
  ]);

  final nodes = await fetchSubscription(
    'https://example.com/sub.txt',
    client: client,
  );

  expect(nodes, hasLength(1));
  expect(client.requestCount, 3);
});

test('does not retry an HTTP 404 response', () async {
  final client = SequenceSubscriptionClient([notFoundResponse]);
  await expectLater(
    fetchSubscription('https://example.com/missing', client: client),
    throwsException,
  );
  expect(client.requestCount, 1);
});
```

- [ ] **Step 2: 运行测试并确认红灯**

Run: `flutter test test/subscription_retry_test.dart`

Expected: 第一个测试 FAIL，当前实现首次网络异常即退出。

- [ ] **Step 3: 实现请求级重试**

新增私有请求包装器，最多执行 3 次；只捕获临时网络异常，每次重试写入不含查询参数的诊断日志。保留现有 403 User-Agent 回退逻辑在单次尝试内部。

- [ ] **Step 4: 运行测试并确认绿灯**

Run: `flutter test test/subscription_retry_test.dart test/subscription_tolerance_test.dart test/anytls_support_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/core/subscription.dart test/subscription_retry_test.dart
git commit -m "fix: retry transient subscription requests"
```

### Task 4: AppProvider 集成快速筛查与统一取消

**Files:**
- Modify: `lib/providers/app_provider.dart`
- Create: `test/app_provider_screening_test.dart`

**Interfaces:**
- Consumes: `runInitialNodeScreening`、`resetNodeHealth`、现有 `checkNodeTcpAvailability` 和 `checkNodeAvailability`。
- Produces: `Future<void> startInitialNodeScreening()`。
- Produces: `void stopNodeChecks()`。
- 保留: `Future<void> checkAllNodes()` 作为手动完整检查。
- Produces: 可测试构造参数 `AppProvider({WindowsProxyService? windowsProxy, SubscriptionLoader? subscriptionLoader, NodeTcpChecker? tcpChecker, NodeFullChecker? fullChecker})`。
- Produces: `typedef SubscriptionLoader = Future<List<VpnNode>> Function(String url, void Function(String message) onDiagnostic)`。
- Produces: `typedef NodeTcpChecker = Future<health.HealthCheckResult> Function(VpnNode node)`。
- Produces: `typedef NodeFullChecker = Future<health.HealthCheckResult> Function(VpnNode node, String corePath, String runtimeDir)`。

- [ ] **Step 1: 编写导入先取消旧批次的失败测试**

```dart
test('new import cancels the running check before requesting subscription',
    () async {
  late AppProvider provider;
  var checkingWhenRequestStarted = true;
  provider = AppProvider(
    subscriptionLoader: (url, onDiagnostic) async {
      checkingWhenRequestStarted = provider.runtime.checkingNodes;
      return [newNode];
    },
    tcpChecker: (node) => controlledTcp.future,
    fullChecker: (node, corePath, runtimeDir) async => availableResult,
  );

  await provider.importSubscription('https://example.com/first');
  final secondImport =
      provider.importSubscription('https://example.com/second');
  controlledTcp.complete(unavailableResult);
  await secondImport;

  expect(checkingWhenRequestStarted, isFalse);
  expect(provider.nodes.map((node) => node.id), contains(newNode.id));
});
```

- [ ] **Step 2: 编写停止后状态清理失败测试**

```dart
test('stopNodeChecks keeps completed results and resets unfinished nodes',
    () async {
  final first = Completer<health.HealthCheckResult>();
  final second = Completer<health.HealthCheckResult>();
  final provider = AppProvider(
    subscriptionLoader: (url, onDiagnostic) async => [nodeA, nodeB],
    tcpChecker: (node) async => availableResult,
    fullChecker: (node, corePath, runtimeDir) =>
        node.id == nodeA.id ? first.future : second.future,
  );
  await provider.importSubscription('https://example.com/sub');
  first.complete(availableResult);
  await Future<void>.delayed(Duration.zero);

  provider.stopNodeChecks();
  second.complete(unavailableResult);
  await Future<void>.delayed(Duration.zero);

  expect(provider.runtime.checkingNodes, isFalse);
  expect(provider.nodes.singleWhere((n) => n.id == nodeA.id).healthStatus,
      HealthStatus.available);
  expect(provider.nodes.singleWhere((n) => n.id == nodeB.id).healthStatus,
      HealthStatus.unknown);
});
```

- [ ] **Step 3: 运行测试并确认红灯**

Run: `flutter test test/app_provider_screening_test.dart`

Expected: FAIL，因为快速筛查和公开取消入口尚不存在。

- [ ] **Step 4: 集成调度器与取消入口**

实现规则：

```dart
void stopNodeChecks() {
  _latencyBatchId++;
  _nodes = _nodes
      .map((node) => node.healthStatus == HealthStatus.checking
          ? resetNodeHealth(node)
          : node)
      .toList();
  _runtime = _runtime.copyWith(checkingNodes: false);
  notifyListeners();
}
```

- `initialize()` 恢复节点后调用 `startInitialNodeScreening()`。
- `importSubscription()` 在请求前调用 `stopNodeChecks()`，成功替换节点后调用 `startInitialNodeScreening()`。
- `importSubscriptionText()` 成功替换节点后也调用 `startInitialNodeScreening()`，保持粘贴文本和 URL 导入行为一致。
- `checkAllNodes()` 继续全量真实验证，但循环领取任务前检查批次编号。
- 调度事件只在批次编号仍有效时更新节点。
- 任务正常结束、取消和超时都将 `checkingNodes` 设为 false，并持久化已完成结果。

- [ ] **Step 5: 运行测试并确认绿灯**

Run: `flutter test test/app_provider_screening_test.dart test/initial_node_screening_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/providers/app_provider.dart test/app_provider_screening_test.dart
git commit -m "feat: integrate cancellable startup screening"
```

### Task 5: 检查/停止双态界面

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_localizations.dart`
- Modify: `lib/l10n/app_localizations_zh.dart`
- Modify: `lib/l10n/app_localizations_en.dart`
- Modify: `test/dashboard_responsive_test.dart`

**Interfaces:**
- Consumes: `AppProvider.stopNodeChecks()` 和 `RuntimeState.checkingNodes`。
- Produces: 检查运行时可点击的“停止”按钮；空节点且未检查时才禁用按钮。

- [ ] **Step 1: 编写失败的组件测试**

```dart
testWidgets('health check button becomes a working stop button',
    (tester) async {
  SharedPreferences.setMockInitialValues({});
  final pending = Completer<health.HealthCheckResult>();
  final provider = AppProvider(
    subscriptionLoader: (url, onDiagnostic) async => [testNode],
    tcpChecker: (node) async => availableResult,
    fullChecker: (node, corePath, runtimeDir) => pending.future,
  );
  await provider.importSubscription('https://example.com/sub');
  await tester.pumpWidget(buildDashboard(provider));
  await tester.pump();

  expect(find.text('停止'), findsOneWidget);
  await tester.tap(find.text('停止'));
  await tester.pump();
  expect(provider.runtime.checkingNodes, isFalse);
});
```

- [ ] **Step 2: 运行测试并确认红灯**

Run: `flutter test test/dashboard_responsive_test.dart`

Expected: FAIL，当前检查中按钮被禁用且只显示“检查中”。

- [ ] **Step 3: 实现按钮和本地化文本**

```dart
onPressed: checkingNodes
    ? onStopChecks
    : (nodes.isEmpty ? null : onCheckAll),
child: Text(checkingNodes ? l10n.stopChecking : l10n.check),
```

中文 `stopChecking` 为“停止”，英文为“Stop”。桌面、平板和窄屏使用同一个头部动作组件，不增加第二套行为。

- [ ] **Step 4: 运行测试并确认绿灯**

Run: `flutter test test/dashboard_responsive_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/screens/dashboard_screen.dart lib/l10n test/dashboard_responsive_test.dart
git commit -m "feat: allow stopping node checks"
```

### Task 6: 综合回归与文档记录

**Files:**
- Modify: `PROJECT_SUMMARY.md`

**Interfaces:**
- Records: 快速筛查时间预算、最低目标、手动检查行为、取消语义和订阅重试规则。

- [ ] **Step 1: 更新项目摘要**

在 Windows 最近迭代中记录：全节点 TCP 预筛、15/45 秒时间预算、快速窗口内不限 5 个、检查可终止、导入前取消旧检查、临时网络错误重试。

- [ ] **Step 2: 运行目标测试集**

Run:

```powershell
flutter test test/node_latency_test.dart test/initial_node_screening_test.dart test/subscription_retry_test.dart test/app_provider_screening_test.dart test/dashboard_responsive_test.dart test/subscription_tolerance_test.dart test/anytls_support_test.dart test/singbox_service_test.dart
```

Expected: All tests passed。

- [ ] **Step 3: 运行静态检查**

Run:

```powershell
flutter analyze lib/core/models/node.dart lib/core/node_latency.dart lib/core/initial_node_screening.dart lib/core/subscription.dart lib/providers/app_provider.dart lib/screens/dashboard_screen.dart
```

Expected: No issues found。

- [ ] **Step 4: 提交文档**

```powershell
git add PROJECT_SUMMARY.md
git commit -m "docs: record adaptive node screening"
```
