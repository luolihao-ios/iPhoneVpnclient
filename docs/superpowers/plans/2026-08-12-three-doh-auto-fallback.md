# 三组 DoH 自动切换实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Forge VPN 内置 Cloudflare、Google、Quad9 三组代理 DoH，并在连接阶段通过真实 HTTP 204 验证自动切换到可用解析器。

**Architecture:** 用独立的 DNS 提供器模型生成确定性的 sing-box 配置，用纯 Dart 协调器管理三次有限尝试、成功项持久化和取消代次。AppProvider 为 iOS、Android、Windows 提供统一的启动、等待连接、204 验证和停止闭包；移动端验证走系统 TUN，Windows 验证显式走本地 HTTP 代理。

**Tech Stack:** Flutter/Dart、SharedPreferences、dart:io、sing-box 1.13.14、iOS NetworkExtension、Android VpnService、Flutter Test。

## Global Constraints

- 只内置 Cloudflare、Google、Quad9，不增加自定义 DNS 导入界面。
- DoH 固定走 HTTPS 443，并通过当前 `proxy` 出站；不能重新使用 DoT 853。
- 智能分流继续使用“中国域名 + 中国 IP”规则集，节点服务器域名始终用本地 DNS。
- 每次用户连接最多尝试三组，每组一次；HTTP 204 验证时限固定为 5 秒。
- 只有收到 `http://www.gstatic.com/generate_204` 的 HTTP 204 才算成功。
- 用户断开、切换节点或发起新连接时取消旧序列；迟到回调不能覆盖新状态。
- Flutter 测试、Flutter 构建和真机安装由用户执行；实现者负责提供精确命令并根据结果继续修正。
- 新增界面提示和项目文档使用中文；诊断日志不得包含密码、UUID、密钥或订阅查询参数。

---

## 文件结构

- Create: `lib/core/remote_dns.dart` — 三组解析器元数据、稳定标识解析、轮换顺序。
- Create: `lib/core/dns_fallback_coordinator.dart` — 有限尝试、取消代次、切换日志和最终结果。
- Create: `lib/core/connection_health.dart` — 移动端 TUN 与桌面 HTTP 代理的 HTTP 204 验证。
- Modify: `lib/core/singbox_config.dart` — 按当前提供器生成 DoH 服务器和 DNS 规则。
- Modify: `lib/services/singbox_service.dart` — Windows 启动时接收当前 DNS 提供器。
- Modify: `lib/providers/app_provider.dart` — 三端接入协调器、等待移动端状态、持久化成功项。
- Create: `test/remote_dns_test.dart` — 提供器元数据与轮换顺序测试。
- Create: `test/dns_fallback_coordinator_test.dart` — 成功、回退、全部失败和取消测试。
- Create: `test/connection_health_test.dart` — HTTP 204、非 204、超时与桌面代理验证测试。
- Modify: `test/anytls_support_test.dart` — 新 DNS 配置与路由规则回归测试。
- Modify: `test/singbox_service_test.dart` — Windows 控制器透传解析器测试。
- Create: `test/app_provider_dns_fallback_source_test.dart` — 移动状态等待、日志和持久化接线的源码回归检查。
- Modify: `PROJECT_SUMMARY.md` — 中文记录本轮 DNS 污染修复与真机验收项。

---

### Task 1: 定义三组远程 DNS 并生成 sing-box 配置

**Files:**
- Create: `lib/core/remote_dns.dart`
- Modify: `lib/core/singbox_config.dart:1-310`
- Create: `test/remote_dns_test.dart`
- Modify: `test/anytls_support_test.dart:245-355`

**Interfaces:**
- Produces: `enum RemoteDnsProvider { cloudflare, google, quad9 }`
- Produces: `RemoteDnsEndpoint remoteDnsEndpoint(RemoteDnsProvider provider)`
- Produces: `RemoteDnsProvider? parseRemoteDnsProvider(String? value)`
- Produces: `List<RemoteDnsProvider> orderedRemoteDnsProviders(RemoteDnsProvider? preferred)`
- Changes: `buildSingBoxConfig({..., RemoteDnsProvider remoteDnsProvider = RemoteDnsProvider.cloudflare})`

- [ ] **Step 1: 写提供器元数据和轮换顺序的失败测试**

```dart
test('三组 DoH 使用固定 IP、443、TLS 名称和路径', () {
  expect(remoteDnsEndpoint(RemoteDnsProvider.cloudflare), const RemoteDnsEndpoint(
    id: 'cloudflare', name: 'Cloudflare', server: '1.1.1.1',
    port: 443, serverName: 'cloudflare-dns.com', path: '/dns-query'));
  expect(remoteDnsEndpoint(RemoteDnsProvider.google).server, '8.8.8.8');
  expect(remoteDnsEndpoint(RemoteDnsProvider.quad9).serverName, 'dns.quad9.net');
});

test('上次成功项排第一并循环其余提供器', () {
  expect(orderedRemoteDnsProviders(RemoteDnsProvider.google), [
    RemoteDnsProvider.google,
    RemoteDnsProvider.quad9,
    RemoteDnsProvider.cloudflare,
  ]);
});
```

- [ ] **Step 2: 请用户运行失败测试**

Run: `flutter test test/remote_dns_test.dart test/anytls_support_test.dart -r expanded`

Expected: FAIL，提示 `RemoteDnsProvider`、`remoteDnsEndpoint` 或新配置参数不存在；旧的 `dns.final == local` 断言也会失败。

- [ ] **Step 3: 实现不可变的 DNS 提供器模型**

```dart
enum RemoteDnsProvider { cloudflare, google, quad9 }

class RemoteDnsEndpoint {
  const RemoteDnsEndpoint({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    required this.serverName,
    required this.path,
  });

  final String id;
  final String name;
  final String server;
  final int port;
  final String serverName;
  final String path;

  Map<String, dynamic> toSingBoxServer() => {
    'type': 'https',
    'tag': 'remote-$id',
    'server': server,
    'server_port': port,
    'path': path,
    'tls': {'enabled': true, 'server_name': serverName},
    'detour': 'proxy',
  };
}
```

`remoteDnsEndpoint` 用穷尽 `switch` 返回规格中的三组常量；`parseRemoteDnsProvider` 仅接受 `cloudflare/google/quad9`；`orderedRemoteDnsProviders` 从 preferred 所在位置旋转固定列表，非法或空值从 Cloudflare 开始。

- [ ] **Step 4: 修改 sing-box DNS 与路由配置**

配置生成器添加 `remoteDnsProvider`，在非直连模式下将三组 `https` 服务器全部放入 `dns.servers`，并把 `dns.final` 指向当前项的 `remote-<id>`。直连模式仍为 `local`。

```dart
final endpoint = remoteDnsEndpoint(remoteDnsProvider);
final dnsFinal = mode == 'direct' ? 'local' : 'remote-${endpoint.id}';

'dns': {
  'servers': [
    localDnsServer,
    for (final provider in RemoteDnsProvider.values)
      remoteDnsEndpoint(provider).toSingBoxServer(),
  ],
  'rules': _dnsRulesForNode(node, mode),
  'final': dnsFinal,
  'strategy': 'prefer_ipv4',
},
```

把 UDP 53 直连例外缩为 `114.114.114.114/32`、`223.5.5.5/32`，移除 `1.1.1.1/32`，防止 Cloudflare DoH 被强制直连。`route.default_domain_resolver.server` 保持 `local`，只负责节点及规则集下载启动阶段的域名拨号。

- [ ] **Step 5: 补齐配置断言**

在 `test/anytls_support_test.dart` 明确断言：

```dart
final dns = (config['dns'] as Map).cast<String, dynamic>();
expect(dns['final'], 'remote-google');
expect((dns['servers'] as List).cast<Map>(), contains(predicate<Map>((server) {
  return server['tag'] == 'remote-google' &&
      server['type'] == 'https' &&
      server['server'] == '8.8.8.8' &&
      server['server_port'] == 443 &&
      server['path'] == '/dns-query' &&
      server['detour'] == 'proxy' &&
      (server['tls'] as Map)['server_name'] == 'dns.google';
})));
```

同时覆盖智能分流的 `geosite-cn -> local`、全局代理不含该 DNS 规则、直连模式 `final == local`、节点域名走 local、DoH IP 不在强制直连 CIDR 中。

- [ ] **Step 6: 请用户运行通过测试**

Run: `flutter test test/remote_dns_test.dart test/anytls_support_test.dart -r expanded`

Expected: PASS。

- [ ] **Step 7: 提交配置单元**

```powershell
git add lib/core/remote_dns.dart lib/core/singbox_config.dart test/remote_dns_test.dart test/anytls_support_test.dart
git commit -m "feat: add three proxy DoH providers"
```

---

### Task 2: 实现可取消的三组自动切换协调器

**Files:**
- Create: `lib/core/dns_fallback_coordinator.dart`
- Create: `test/dns_fallback_coordinator_test.dart`

**Interfaces:**
- Consumes: `RemoteDnsProvider`、`orderedRemoteDnsProviders`
- Produces: `typedef StartDnsAttempt = Future<void> Function(RemoteDnsProvider provider)`
- Produces: `typedef StopDnsAttempt = Future<void> Function()`
- Produces: `class DnsAttemptResult`，包含 `bool ok`、`int? statusCode`、`String? error`
- Produces: `typedef VerifyDnsAttempt = Future<DnsAttemptResult> Function()`
- Produces: `class DnsFallbackCoordinator`，公开 `Future<RemoteDnsProvider> connect(...)` 与 `void cancel()`
- Produces: `class DnsFallbackCancelled implements Exception`
- Produces: `class AllDnsProvidersFailed implements Exception`

- [ ] **Step 1: 写失败、成功、全部失败和取消测试**

```dart
test('第一组失败后停止并切到第二组', () async {
  final events = <String>[];
  var probes = 0;
  final coordinator = DnsFallbackCoordinator(onLog: events.add);

  final selected = await coordinator.connect(
    preferred: RemoteDnsProvider.cloudflare,
    start: (provider) async => events.add('start:${provider.name}'),
    stop: () async => events.add('stop'),
    verify: () async => ++probes == 1
        ? const DnsAttemptResult.failed('timeout')
        : const DnsAttemptResult.passed(statusCode: 204),
  );

  expect(selected, RemoteDnsProvider.google);
  expect(events, containsAllInOrder([
    'start:cloudflare', 'stop', 'start:google',
  ]));
});
```

再增加：首组成功不调用 stop、三组失败调用三次 stop 并抛 `AllDnsProvidersFailed`、`cancel()` 后不启动下一组、旧连接迟到验证不会完成新一代连接。

- [ ] **Step 2: 请用户运行失败测试**

Run: `flutter test test/dns_fallback_coordinator_test.dart -r expanded`

Expected: FAIL，提示协调器和结果类型不存在。

- [ ] **Step 3: 实现最小协调器**

协调器内部维护递增 `_generation`。`connect` 开始时取得本地 generation；在 start、verify、stop 的每个 await 后调用 `_ensureActive(generation)`。失败后必须先 stop，再记录切换日志；成功立即返回提供器。三组失败统一抛出：

```dart
throw AllDnsProvidersFailed(
  '三组远程 DNS/代理链路均不可用，请检查节点或网络',
  failures,
);
```

日志使用规格固定格式，`reason` 先折叠换行并限制长度，不拼接配置 JSON。

- [ ] **Step 4: 请用户运行通过测试**

Run: `flutter test test/dns_fallback_coordinator_test.dart -r expanded`

Expected: PASS。

- [ ] **Step 5: 提交协调器**

```powershell
git add lib/core/dns_fallback_coordinator.dart test/dns_fallback_coordinator_test.dart
git commit -m "feat: coordinate automatic DoH fallback"
```

---

### Task 3: 实现必须经过 VPN 的 HTTP 204 验证

**Files:**
- Create: `lib/core/connection_health.dart`
- Create: `test/connection_health_test.dart`
- Modify: `lib/core/node_health.dart:143-185`

**Interfaces:**
- Consumes: `DnsAttemptResult`
- Produces: `final Uri vpnHealthCheckUri`
- Produces: `Future<DnsAttemptResult> verifyThroughSystemTun({Duration timeout = const Duration(seconds: 5), HttpClient? client})`
- Produces: `Future<DnsAttemptResult> verifyThroughDesktopProxy({int proxyPort = defaultHttpPort, Duration timeout = const Duration(seconds: 5), Proxy204Requester requester = requestHttp204ThroughProxy})`
- Reuses: `requestHttp204ThroughProxy`、`isHttp204Response`

- [ ] **Step 1: 写精确状态码测试**

使用本地 `HttpServer` 验证移动请求：204 为成功、200 为失败、超时为失败。桌面函数注入 requester，验证固定传入 `defaultHttpPort`、`vpnHealthCheckUri` 和 5000ms，并且只有状态行 `HTTP/1.1 204` 成功。

```dart
test('桌面验证必须经过本地 HTTP 代理且只接受 204', () async {
  final result = await verifyThroughDesktopProxy(
    requester: ({required proxyPort, required target, required timeoutMs}) async {
      expect(proxyPort, defaultHttpPort);
      expect(target, vpnHealthCheckUri);
      expect(timeoutMs, 5000);
      return 'HTTP/1.1 200 OK';
    },
  );
  expect(result.ok, isFalse);
  expect(result.statusCode, 200);
});
```

- [ ] **Step 2: 请用户运行失败测试**

Run: `flutter test test/connection_health_test.dart test/node_health_test.dart -r expanded`

Expected: FAIL，提示新探测接口不存在。

- [ ] **Step 3: 实现移动 TUN 验证**

`verifyThroughSystemTun` 使用 `HttpClient.getUrl(vpnHealthCheckUri)`，设置 `followRedirects = false`，整体用 5 秒 timeout，并在 finally 中关闭客户端。普通移动请求由 iOS/Android 系统 VPN 路由进入 TUN，不设置直连 socket 或自定义代理。

- [ ] **Step 4: 实现桌面代理验证并复用状态行解析**

`verifyThroughDesktopProxy` 调用现有 `requestHttp204ThroughProxy`，解析第一行状态码；网络异常和超时返回 failed 结果而不向上泄漏底层 Socket 对象。把节点健康检查中的重复目标常量替换为 `vpnHealthCheckUri.toString()`，不改变现有节点检查行为。

- [ ] **Step 5: 请用户运行通过测试**

Run: `flutter test test/connection_health_test.dart test/node_health_test.dart -r expanded`

Expected: PASS。

- [ ] **Step 6: 提交联网验证**

```powershell
git add lib/core/connection_health.dart lib/core/node_health.dart test/connection_health_test.dart test/node_health_test.dart
git commit -m "feat: verify active VPN with HTTP 204"
```

---

### Task 4: 让 Windows 控制器接收当前 DoH 提供器

**Files:**
- Modify: `lib/services/singbox_service.dart:67-150`
- Modify: `test/singbox_service_test.dart`

**Interfaces:**
- Consumes: `RemoteDnsProvider`
- Changes: `SingBoxController.connect({required VpnNode node, String mode = 'global', bool tunEnabled = false, RemoteDnsProvider remoteDnsProvider = RemoteDnsProvider.cloudflare})`

- [ ] **Step 1: 写配置透传失败测试**

为 `SingBoxController` 增加可注入的 `ProcessStarter` 或配置构建观察点，测试用假启动器读取写入的 `sing-box.json`，断言 Google 尝试生成 `dns.final == remote-google`，而不是 Cloudflare。

```dart
await controller.connect(
  node: node,
  remoteDnsProvider: RemoteDnsProvider.google,
);
expect(jsonDecode(await configFile.readAsString())['dns']['final'], 'remote-google');
```

- [ ] **Step 2: 请用户运行失败测试**

Run: `flutter test test/singbox_service_test.dart -r expanded`

Expected: FAIL，提示 `remoteDnsProvider` 不是 `connect` 参数，或配置仍为默认项。

- [ ] **Step 3: 最小化修改控制器**

只给 `connect` 增加参数并原样传给 `buildSingBoxConfig`。不要把回退状态放入 `SingBoxController`；进程控制器只负责一次确定的启动。

- [ ] **Step 4: 请用户运行通过测试**

Run: `flutter test test/singbox_service_test.dart -r expanded`

Expected: PASS。

- [ ] **Step 5: 提交 Windows 透传**

```powershell
git add lib/services/singbox_service.dart test/singbox_service_test.dart
git commit -m "feat: pass selected DoH to desktop core"
```

---

### Task 5: 在 AppProvider 接入三端自动切换与状态持久化

**Files:**
- Modify: `lib/providers/app_provider.dart:1-1010`
- Create: `test/app_provider_dns_fallback_source_test.dart`
- Modify: `test/dashboard_responsive_test.dart`

**Interfaces:**
- Consumes: `DnsFallbackCoordinator`、`RemoteDnsProvider`、两种 HTTP 204 verifier。
- Adds constructor injection: `DnsFallbackCoordinator? dnsFallbackCoordinator`、`Future<DnsAttemptResult> Function()? mobileConnectionVerifier`、`Future<DnsAttemptResult> Function()? desktopConnectionVerifier`。
- Adds private persistence key: `_remoteDnsProviderKey = 'remote_dns_provider'`。
- Adds private methods: `_startDnsAttempt(...)`、`_stopDnsAttempt()`、`_waitForMobileConnected(int generation)`、`_verifyCurrentConnection()`。

- [ ] **Step 1: 写 AppProvider 接线失败测试**

源码回归测试必须检查以下稳定接线，避免平台单例难以在宿主机单测时遗漏移动端路径：

```dart
expect(source, contains("static const _remoteDnsProviderKey = 'remote_dns_provider';"));
expect(source, contains('DnsFallbackCoordinator'));
expect(source, contains('remoteDnsProvider: provider'));
expect(source, contains('verifyThroughSystemTun'));
expect(source, contains('verifyThroughDesktopProxy'));
expect(source, contains('[dns-fallback]'));
```

在 `dashboard_responsive_test.dart` 用 SharedPreferences mock 验证初始化能恢复 `remote_dns_provider=google`，协调器成功回调后能保存新值。若直接模拟平台困难，持久化提取为两个可见测试函数 `loadPreferredRemoteDns` 和 `savePreferredRemoteDns`，由 AppProvider 调用。

- [ ] **Step 2: 请用户运行失败测试**

Run: `flutter test test/app_provider_dns_fallback_source_test.dart test/dashboard_responsive_test.dart -r expanded`

Expected: FAIL，提示持久化键、恢复逻辑和协调器接线不存在。

- [ ] **Step 3: 恢复并保存上次成功项**

`initialize` 的 SharedPreferences 恢复阶段读取稳定字符串并通过 `parseRemoteDnsProvider` 校验。只有协调器返回成功提供器后才保存；失败、取消、应用退出不覆盖旧值。

- [ ] **Step 4: 为移动端等待真实 connected 状态**

增加连接代次和当前等待 completer。iOS/Android 收到 `connected` 时：

- 若正在自动验证，只完成当前 completer，日志写“隧道已连接，正在验证”，暂不把 `_runtime.connected` 设为 true。
- 若不是本轮连接（例如应用初始化恢复系统 VPN），保持现有状态恢复行为。
- 收到 `error/disconnected` 时，使当前等待以错误完成。

等待函数在用户取消或新连接产生后抛 `DnsFallbackCancelled`，迟到的 `connected` 不得完成新 completer。

- [ ] **Step 5: 统一三端单次启动和停止**

`_startDnsAttempt` 根据平台执行一次确定连接：

```dart
final config = buildSingBoxConfig(
  node: node,
  mode: settings.routeMode,
  tunEnabled: true,
  remoteDnsProvider: provider,
  logLevel: _isiOS ? 'debug' : 'info',
);
```

iOS/Android 调用原生 connect 后等待对应 connected 回调；Windows 调用 `_controller.connect(... remoteDnsProvider: provider)`，然后按现有设置启用或恢复系统代理。`_stopDnsAttempt` 必须等待移动端 disconnect；Windows 停止进程并恢复系统代理。

- [ ] **Step 6: 用协调器重写非直连连接流程**

`connect` 先取消旧 generation。`routeMode == direct` 时沿用单次本地 DNS 连接；其他模式调用协调器：

```dart
final selected = await _dnsFallbackCoordinator.connect(
  preferred: _preferredRemoteDns,
  start: (provider) => _startDnsAttempt(node, mergedSettings, provider),
  verify: _verifyCurrentConnection,
  stop: _stopDnsAttempt,
);
```

成功后才设 `_runtime.connected = true`、保存 selected 并启动 Windows 流量统计。三组失败时确保 `_runtime.connected = false`、写中文提示并重新抛出用户可见异常。

- [ ] **Step 7: 接入取消入口与脱敏日志**

`disconnect`、`selectNode`、新的 `connect` 和 `dispose` 均调用 coordinator.cancel。日志逐次输出提供器名、结果和切换方向，不输出配置 JSON；现有 iOS AnyTLS 脱敏摘要保留。

- [ ] **Step 8: 请用户运行 Provider 回归测试**

Run: `flutter test test/app_provider_dns_fallback_source_test.dart test/dashboard_responsive_test.dart test/app_provider_screening_test.dart -r expanded`

Expected: PASS。

- [ ] **Step 9: 提交三端集成**

```powershell
git add lib/providers/app_provider.dart test/app_provider_dns_fallback_source_test.dart test/dashboard_responsive_test.dart
git commit -m "feat: auto-switch DoH during VPN connection"
```

---

### Task 6: 全量回归、项目文档和真机验收

**Files:**
- Modify: `PROJECT_SUMMARY.md`

**Interfaces:**
- Consumes: 前五个任务的公开接口。
- Produces: 中文迭代记录、用户可执行命令和 iPhone 验收清单。

- [ ] **Step 1: 更新中文项目记录**

在 `PROJECT_SUMMARY.md` 新增“2026-08-12 三组 DoH 自动切换”章节，记录：DNS 污染证据、三组 443 DoH、上次成功项优先、HTTP 204 判定、智能/全局/直连规则、三端共用和未完成的真机项。

- [ ] **Step 2: 执行静态检查**

Run: `dart format --output=none --set-exit-if-changed lib test`

Expected: exit 0。该命令若会调用 Flutter SDK，由用户运行并反馈结果。

- [ ] **Step 3: 请用户执行定向测试**

Run:

```powershell
flutter test test/remote_dns_test.dart test/anytls_support_test.dart test/dns_fallback_coordinator_test.dart test/connection_health_test.dart test/node_health_test.dart test/singbox_service_test.dart test/app_provider_dns_fallback_source_test.dart test/dashboard_responsive_test.dart test/app_provider_screening_test.dart -r expanded
```

Expected: All tests passed。

- [ ] **Step 4: 请用户执行完整 Flutter 回归**

Run: `flutter test -r expanded`

Expected: All tests passed。若现有未提交的 `test/subscription_import_card_test.dart` 失败，先区分用户原有改动与本功能回归，不覆盖该文件。

- [ ] **Step 5: iOS 真机验收**

通过 GitHub Actions 构建最新 IPA，卸载旧版后安装。依次验证：

1. 智能分流连接后，微信/抖音等国内应用正常，Safari 打开 Google/YouTube 正常。
2. 全局代理连接后，Google/YouTube 正常且日志显示当前 DoH。
3. 将第一组测试地址临时改成不可达值构建诊断包，确认日志出现 Cloudflare 失败、自动切到 Google、最终 204 成功；验收后恢复正式地址。
4. 三组全部不可达的诊断测试中，应用最终显示未连接并给出中文错误，不能保持绿色 Connected。
5. 主动断开或切换节点时不再继续自动重连。

- [ ] **Step 6: Android 与 Windows 验收**

Android 验证智能/全局模式和自动切换日志；Windows 验证 HTTP 204 请求明确经过 `127.0.0.1:2080`，断开及三组失败后系统代理恢复。

- [ ] **Step 7: 提交文档与最终整理**

```powershell
git add PROJECT_SUMMARY.md
git commit -m "docs: record three DoH fallback rollout"
```

- [ ] **Step 8: 推送 main**

确认 `git status --short` 只剩用户原有的 `test/subscription_import_card_test.dart` 改动后：

```powershell
git push origin main
```
