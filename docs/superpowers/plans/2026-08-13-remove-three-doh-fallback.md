# 移除三组 DoH 自动回退实施计划

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 移除 Windows、Android、iOS 正式连接阶段的 Cloudflare/Google/Quad9 自动轮换和连接后 HTTP 204 强制验证，恢复一次连接即由平台状态决定结果，并解决 Windows 默认 `cache.db` 权限故障。

**Architecture:** 共享 sing-box 配置恢复为单个本地 UDP DNS，正式连接路径只调用一次各平台启动方法；节点列表的 HTTP 204 可用性检查保持原样。Windows 控制器在生成正式运行配置时显式关闭 `experimental.cache_file`，避免 sing-box 在应用工作目录创建或锁定默认 `cache.db`。

**Tech Stack:** Flutter/Dart、sing-box JSON、flutter_test、SharedPreferences、Windows process runner

---

## 约束

- 不修改节点列表的 HTTP 204 检查、3 秒单节点上限和全节点检查行为。
- 不修改订阅解析、节点协议、系统代理恢复、路由模式或桌面 UI。
- Android/iOS 仍等待平台回调确认隧道启动成功，但不再执行额外联网验证或 DNS 轮换。
- Windows 正式连接关闭缓存；共享配置生成器的 `cacheFile` 默认值暂不修改，避免影响其他明确依赖缓存的调用方。
- 保留旧设计文档作为历史记录，在当前项目文档中明确三组 DoH 已回退。

### Task 1: 用回归测试锁定简单 DNS 配置

**Files:**
- Modify: `test/anytls_support_test.dart`
- Modify: `lib/core/singbox_config.dart`

- [ ] **Step 1: 把远程 DoH 配置测试改成当前目标**

删除测试对 `RemoteDnsProvider` 的依赖，新增或改写断言：

```dart
test('正式连接只生成本地 DNS，不包含三组远程 DoH', () {
  final config = buildSingBoxConfig(node: node);
  final dns = (config['dns'] as Map).cast<String, dynamic>();
  final servers = (dns['servers'] as List).cast<Map>();

  expect(dns['final'], 'local');
  expect(servers.map((server) => server['tag']), ['local']);
  expect(servers.single['server'], '223.5.5.5');
  expect(servers.where((server) => server['type'] == 'https'), isEmpty);
});
```

智能分流测试继续确认节点服务器域名和 `geosite-cn` 使用 `local`；不再断言海外域名指向远程 DoH。

- [ ] **Step 2: 让用户运行定向测试，确认旧实现失败**

```powershell
flutter test test/anytls_support_test.dart
```

预期：旧实现仍生成 `remote-cloudflare/google/quad9`，新断言失败。

- [ ] **Step 3: 简化共享 DNS 配置**

在 `lib/core/singbox_config.dart`：

- 移除 `remote_dns.dart` 导入和 `remoteDnsProvider` 参数。
- 删除 `_foreignDomainOverrides` 仅为远程 DNS 选择服务的规则。
- `_dnsRulesForNode` 只保留节点域名走 `local`，智能分流保留 `geosite-cn -> local`。
- `dns.servers` 只保留 `local` UDP `223.5.5.5:53`。
- `dns.final` 对所有路由模式固定为 `local`。
- 保留现有中国规则集、路由出口和 DNS 劫持规则。

- [ ] **Step 4: 格式化并提交配置回退**

```powershell
dart format lib/core/singbox_config.dart test/anytls_support_test.dart
git add lib/core/singbox_config.dart test/anytls_support_test.dart
git commit -m "fix: restore simple DNS configuration"
```

### Task 2: 把正式连接恢复为单次平台启动

**Files:**
- Delete: `lib/core/remote_dns.dart`
- Delete: `lib/core/dns_fallback_coordinator.dart`
- Delete: `lib/core/connection_health.dart`
- Delete: `test/remote_dns_test.dart`
- Delete: `test/dns_fallback_coordinator_test.dart`
- Delete: `test/connection_health_test.dart`
- Delete: `test/app_provider_dns_fallback_test.dart`
- Create: `test/app_provider_connection_test.dart`
- Modify: `lib/providers/app_provider.dart`
- Modify: `lib/services/singbox_service.dart`

- [ ] **Step 1: 新增一次连接回归测试**

使用注入的 `connectionAttemptStarter` 构造 `AppProvider`，导入并选中测试节点后调用 `connect()`，断言：

```dart
expect(starts, 1);
expect(provider.runtime.connected, isTrue);
expect(provider.runtime.proxyWarning, isEmpty);
```

再增加启动抛错用例，断言只调用一次且运行状态保持未连接；测试 API 不再接收 DNS 提供器、验证器、停止器或协调器。

- [ ] **Step 2: 让用户运行测试，确认新 API 尚未实现**

```powershell
flutter test test/app_provider_connection_test.dart
```

预期：构造函数/连接启动器签名不匹配，测试失败。

- [ ] **Step 3: 删除三组回退状态和持久化**

在 `lib/providers/app_provider.dart`：

- 删除三项核心导入、`RemoteDnsProvider`、`DnsFallbackCoordinator`、`ConnectionVerifier` 和相关构造参数/字段/getter。
- 删除 `remote_dns_provider` SharedPreferences 读取和写入。
- `connect()` 对所有路由模式只调用一次 `_startConnectionAttempt(node, settings)`；成功后设为已连接并启动统计，失败后保持未连接并原样抛错。
- Android/iOS 保留现有 15 秒平台连接回调等待；删除 `_validatingConnection` 对状态回调的抑制条件，让真实平台状态直接更新界面。
- `disconnect()` 直接停止当前平台连接，不再取消 DNS generation。
- `_connectAndroid`、`_connectIOS`、`_connectDesktop` 不再接收或转发 DNS 提供器。

在 `lib/services/singbox_service.dart` 删除 `RemoteDnsProvider` 参数和转发。

- [ ] **Step 4: 删除只服务于旧功能的实现与测试文件**

删除三组 DNS 元数据、协调器、正式连接验证器及其测试。确认仓库中只在旧历史文档里保留 `RemoteDns`/`DnsFallback` 文本：

```powershell
rg -n "RemoteDns|remoteDns|DnsFallback|dnsFallback|verifyThroughSystemTun|verifyThroughDesktopProxy" lib test
```

预期：无匹配。

- [ ] **Step 5: 运行连接相关回归测试**

```powershell
flutter test test/app_provider_connection_test.dart test/dashboard_responsive_test.dart test/ios_connection_state_test.dart test/android_connection_state_test.dart
```

如个别平台状态测试文件名称与仓库不一致，先用 `rg --files test` 选择现有对应文件，不新增空测试替代。

- [ ] **Step 6: 格式化并提交连接回退**

```powershell
dart format lib/providers/app_provider.dart lib/services/singbox_service.dart test/app_provider_connection_test.dart
git add lib/providers/app_provider.dart lib/services/singbox_service.dart lib/core/remote_dns.dart lib/core/dns_fallback_coordinator.dart lib/core/connection_health.dart test/remote_dns_test.dart test/dns_fallback_coordinator_test.dart test/connection_health_test.dart test/app_provider_dns_fallback_test.dart test/app_provider_connection_test.dart
git commit -m "fix: remove forced DoH connection fallback"
```

### Task 3: 禁用 Windows 正式连接的默认 cache.db

**Files:**
- Modify: `test/singbox_service_test.dart`
- Modify: `lib/services/singbox_service.dart`

- [ ] **Step 1: 将旧 DoH 控制器测试改成缓存回归测试**

复用现有 Windows 长运行假核心，连接后读取生成的 `sing-box.json`：

```dart
final experimental = (config['experimental'] as Map).cast<String, dynamic>();
expect(experimental, isNot(contains('cache_file')));
```

同时确认 `dns.final == 'local'`，从服务层同时覆盖 DNS 回退与 Windows 缓存故障。

- [ ] **Step 2: 让用户运行测试，确认旧实现仍启用缓存**

```powershell
flutter test test/singbox_service_test.dart
```

预期：当前正式连接配置含 `experimental.cache_file`，断言失败。

- [ ] **Step 3: 在 Windows 正式连接处明确关闭缓存**

在 `SingBoxController.connect()` 调用 `buildSingBoxConfig` 时传入：

```dart
cacheFile: false,
```

不要修改节点健康检查和共享默认值。

- [ ] **Step 4: 运行 Windows 相关回归测试**

```powershell
flutter test test/singbox_service_test.dart test/windows_proxy_service_test.dart test/windows_vpn_diagnostics_test.dart test/desktop_vpn_diagnostics_test.dart
```

- [ ] **Step 5: 格式化并提交缓存修复**

```powershell
dart format lib/services/singbox_service.dart test/singbox_service_test.dart
git add lib/services/singbox_service.dart test/singbox_service_test.dart
git commit -m "fix: disable desktop cache database"
```

### Task 4: 文档、版本标记和完整静态检查

**Files:**
- Modify: `pubspec.yaml`
- Modify: `PROJECT_SUMMARY.md`
- Modify: `docs/recent-iterations.md`

- [ ] **Step 1: 更新可见构建标记**

将 `pubspec.yaml` 从 `0.1.3+4` 提升到 `0.1.3+5`，便于截图确认运行的是本次修复版本；发行版本仍为 `0.1.3`。

- [ ] **Step 2: 更新项目文档**

在 `PROJECT_SUMMARY.md` 顶部新增本次回退章节，写明：

- 三组代理 DoH 与正式连接后 HTTP 204 强制验证已移除。
- 三端恢复一次连接，节点列表 HTTP 204 检查不变。
- Windows 正式配置禁用默认 `cache.db`，原因是日志中的 `Access is denied`。
- 当前 DNS 恢复为本地 `223.5.5.5`，智能分流规则保持。

在 `docs/recent-iterations.md` 将当前版本说明改为 `0.1.3+5`，删除“当前仍启用三组 DoH”的表述并记录此次回退。历史规格/计划文件不删除。

- [ ] **Step 3: 运行静态检查和完整测试**

把以下命令交给用户运行：

```powershell
flutter analyze lib/core/singbox_config.dart lib/providers/app_provider.dart lib/services/singbox_service.dart
flutter test
```

依赖“有新版但与约束不兼容”的提示不是失败；要求最终输出分别为 `No issues found!` 和 `All tests passed!`。

- [ ] **Step 4: 核对工作树并提交文档与版本**

先确认不包含用户已有的 `test/subscription_import_card_test.dart` 和 `docs/Forge-Store-Logo-1080.png`：

```powershell
git status --short
git diff --check
git add pubspec.yaml PROJECT_SUMMARY.md docs/recent-iterations.md
git commit -m "docs: record DNS fallback rollback"
```

### Task 5: Windows 真机验收

- [ ] **Step 1: 关闭正在运行的旧版 Forge VPN**

从托盘右键退出，确认任务管理器中没有 `forge_vpn_flutter.exe` 和 `sing-box.exe`，避免链接器 `LNK1104`。

- [ ] **Step 2: 构建并运行新版本**

```powershell
flutter build windows --release
```

运行 `build\windows\x64\runner\Release\forge_vpn_flutter.exe`，设置页应显示 `0.1.3.005`。

- [ ] **Step 3: 验证三个关键场景**

1. Windows 原先可用节点可以连接，不再显示“三组远程 DNS/代理链路均不可用”。
2. 日志不再出现 `[dns-fallback]`，也不再出现 `initialize cache-file: open cache.db: Access is denied`。
3. Android/iOS 原先可用节点连接后不会因额外 HTTP 204 验证被主动断开。

- [ ] **Step 4: 如需安装包再单独生成**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_windows_installer.ps1
```

安装包输出到 `E:\workspace\forge-vpn-flutter\dist`；仅在真机验收通过后发布。
