# Clash Hysteria / AnyTLS 兼容性实施计划

> **供执行代理使用：** 必须逐项按测试先行执行；每个任务先写失败测试、确认失败、再写最小实现并验证通过。

**目标：** 让 Forge VPN 解析并正确转换 Clash YAML 中的旧版 Hysteria、带端口范围的 Hysteria2 与兼容字段的 AnyTLS 节点，并提供安全的解析统计日志。

**架构：** 扩展共享的 `VpnNode` 模型保存协议字段，在 `subscription.dart` 的标准化入口兼容 Clash 键名，再由 `singbox_config.dart` 的唯一出站构建器生成合法的 sing-box 配置。解析统计在订阅解析边界生成，Windows、Android、iOS 共享同一结果。

**技术栈：** Flutter、Dart、`flutter_test`、`yaml`、sing-box JSON 配置。

## 全局约束

- 所有新增文档与用户可见说明使用中文。
- 不输出订阅链接、密码、UUID、令牌或代理认证数据到诊断日志。
- 保持 `https://www.gstatic.com/generate_204` 测速目标和现有成功标准不变。
- 不修改未跟踪的 `.flclash-source-inspect/` 与 `docs/Forge-Store-Logo-1080.png`。
- 三端复用共享 Dart 解析与 sing-box 配置，不复制平台特定实现。

---

### 任务 1：为模型和 Hysteria2 端口范围建立回归测试

**文件：**
- 修改：`test/hysteria2_support_test.dart`
- 修改：`test/node_storage_test.dart`
- 修改：`lib/core/models/node.dart`

**接口：**
- 产生：`VpnNode.serverPorts`（`List<String>?`）与 `VpnNode.hopInterval`（`String?`）。
- 消费：`VpnNode.toJson()`、`VpnNode.fromJson()`、`VpnNode.copyWith()`。

- [ ] **步骤 1：写入失败测试**

```dart
test('保留 Clash Hysteria2 端口范围和跳跃间隔', () {
  final node = parseSubscription('''
proxies:
  - name: Hysteria2 range
    type: hysteria2
    server: hy2.example.com
    port: 443
    ports: 22000-27000
    hop-interval: 30
    password: client-password
''').single;

  expect(node.serverPorts, ['22000:27000']);
  expect(node.hopInterval, '30s');
});
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/hysteria2_support_test.dart`

预期：失败，提示 `serverPorts` 或 `hopInterval` 尚不存在。

- [ ] **步骤 3：实现最小模型支持**

在 `VpnNode` 构造器、`copyWith`、`toJson` 和 `fromJson` 中增加可选字段；端口范围持久化为字符串数组，旧记录缺失字段时返回 `null`。

- [ ] **步骤 4：运行测试并确认通过**

运行：`flutter test test/hysteria2_support_test.dart test/node_storage_test.dart`

预期：通过。

- [ ] **步骤 5：提交**

```powershell
git add lib/core/models/node.dart test/hysteria2_support_test.dart test/node_storage_test.dart
git commit -m "feat: preserve Hysteria port ranges"
```

### 任务 2：生成正确的 Hysteria2 `server_ports` 配置

**文件：**
- 修改：`test/hysteria2_support_test.dart`
- 修改：`lib/core/subscription.dart`
- 修改：`lib/core/singbox_config.dart`

**接口：**
- 消费：`VpnNode.serverPorts`、`VpnNode.hopInterval`。
- 产生：端口范围节点仅输出 sing-box `server_ports`，可选输出 `hop_interval`。

- [ ] **步骤 1：写入失败测试**

```dart
test('Hysteria2 端口范围只生成 server_ports', () {
  const node = VpnNode(
    id: 'hy2-range', type: NodeType.hysteria2, name: 'Hysteria2 range',
    server: 'hy2.example.com', port: 443, password: 'client-password',
    serverPorts: ['22000:27000'], hopInterval: '30s',
  );
  final outbound = (buildSingBoxConfig(node: node, includeSocks: false)
      ['outbounds'] as List).first as Map<String, dynamic>;

  expect(outbound['server_ports'], ['22000:27000']);
  expect(outbound.containsKey('server_port'), isFalse);
  expect(outbound['hop_interval'], '30s');
});
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/hysteria2_support_test.dart`

预期：失败，当前配置仍输出 `server_port`。

- [ ] **步骤 3：实现最小解析与配置映射**

将 Clash `ports` / `server-ports` 解析为范围字符串数组；把单值、连字符范围和已使用冒号的范围标准化。`hop-interval` / `hop_interval` 的纯秒数字规范化为 `Ns`。有范围时仅写 `server_ports`。

- [ ] **步骤 4：运行测试并确认通过**

运行：`flutter test test/hysteria2_support_test.dart test/node_health_config_test.dart`

预期：通过。

- [ ] **步骤 5：提交**

```powershell
git add lib/core/subscription.dart lib/core/singbox_config.dart test/hysteria2_support_test.dart
git commit -m "fix: map Clash Hysteria2 port hopping"
```

### 任务 3：支持旧版 Clash Hysteria

**文件：**
- 创建：`test/hysteria_support_test.dart`
- 修改：`lib/core/models/node.dart`
- 修改：`lib/core/subscription.dart`
- 修改：`lib/core/singbox_config.dart`

**接口：**
- 产生：`NodeType.hysteria`。
- 消费：旧版 Clash `auth-str` / `auth_str`、`obfs`、带宽、TLS、端口范围字段。

- [ ] **步骤 1：写入失败测试**

```dart
test('解析 Clash 旧版 Hysteria 并生成 sing-box 出站', () {
  final node = parseSubscription('''
proxies:
  - name: Legacy Hysteria
    type: hysteria
    server: hy.example.com
    port: 9009
    ports: 6000-11000
    auth-str: client-auth
    obfs: obfs-password
    up: 30
    down: 70
    sni: cdn.example.com
''').single;

  expect(node.type, NodeType.hysteria);
  expect(node.password, 'client-auth');
  final outbound = (buildSingBoxConfig(node: node, includeSocks: false)
      ['outbounds'] as List).first as Map<String, dynamic>;
  expect(outbound['type'], 'hysteria');
  expect(outbound['auth_str'], 'client-auth');
  expect(outbound['server_ports'], ['6000:11000']);
});
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/hysteria_support_test.dart`

预期：失败，当前枚举与解析器不支持 `hysteria`。

- [ ] **步骤 3：实现最小旧版 Hysteria 支持**

新增枚举分支、可用性校验和持久化枚举兼容；解析 `auth-str` / `auth_str` 并用现有 `password` 字段保存认证字符串；生成 sing-box `hysteria` 出站，输出带宽、混淆、TLS、端口范围和可选跳跃间隔。

- [ ] **步骤 4：运行测试并确认通过**

运行：`flutter test test/hysteria_support_test.dart test/node_storage_test.dart test/node_health_config_test.dart`

预期：通过。

- [ ] **步骤 5：提交**

```powershell
git add lib/core/models/node.dart lib/core/subscription.dart lib/core/singbox_config.dart test/hysteria_support_test.dart test/node_storage_test.dart
git commit -m "feat: support legacy Clash Hysteria nodes"
```

### 任务 4：补齐 AnyTLS Clash 字段兼容

**文件：**
- 创建：`test/anytls_clash_support_test.dart`
- 修改：`lib/core/subscription.dart`
- 修改：`lib/core/singbox_config.dart`

**接口：**
- 消费：Clash AnyTLS 的 `server-port`、`skip-cert-verify`、`idle-session-check-interval`、`idle-session-timeout`、`min-idle-session`。
- 产生：完整的共享 `NodeType.anytls` 与 sing-box `anytls` outbound。

- [ ] **步骤 1：写入失败测试**

```dart
test('解析使用连字符字段的 Clash AnyTLS 节点', () {
  final node = parseSubscription('''
proxies:
  - name: Clash AnyTLS
    type: anytls
    server: anytls.example.com
    server-port: 443
    password: client-password
    sni: cdn.example.com
    skip-cert-verify: true
    idle-session-check-interval: 15s
    idle-session-timeout: 30s
    min-idle-session: 2
''').single;

  expect(node.port, 443);
  expect(node.insecure, isTrue);
  expect(node.idleSessionCheckInterval, '15s');
  expect(node.idleSessionTimeout, '30s');
  expect(node.minIdleSession, 2);
});
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/anytls_clash_support_test.dart`

预期：失败，当前解析器无法读取 `server-port` 与部分连字符字段。

- [ ] **步骤 3：实现最小键名兼容**

仅在 AnyTLS 标准化分支中补齐连字符与下划线字段；配置生成继续复用现有 AnyTLS 分支，不改变其它协议。

- [ ] **步骤 4：运行测试并确认通过**

运行：`flutter test test/anytls_clash_support_test.dart`

预期：通过。

- [ ] **步骤 5：提交**

```powershell
git add lib/core/subscription.dart lib/core/singbox_config.dart test/anytls_clash_support_test.dart
git commit -m "fix: accept Clash AnyTLS field aliases"
```

### 任务 5：增加无敏感信息的解析统计

**文件：**
- 创建：`test/subscription_parse_diagnostics_test.dart`
- 修改：`lib/core/subscription.dart`
- 修改：`PROJECT_SUMMARY.md`

**接口：**
- 消费：`parseSubscription(rawText, onDiagnostic: ...)`。
- 产生：`subscription parse summary:` 诊断行，包含字节数、短哈希、源类型/已接受类型/跳过类型的计数。

- [ ] **步骤 1：写入失败测试**

```dart
test('Clash 解析诊断按类型统计且不泄露凭据', () {
  final diagnostics = <String>[];
  parseSubscription('''
proxies:
  - {name: supported, type: anytls, server: a.example, port: 443, password: secret}
  - {name: skipped, type: unsupported-protocol, server: b.example, port: 443}
''', onDiagnostic: diagnostics.add);

  final summary = diagnostics.singleWhere(
      (message) => message.startsWith('subscription parse summary:'));
  expect(summary, contains('source={anytls:1, unsupported-protocol:1}'));
  expect(summary, contains('accepted={anytls:1}'));
  expect(summary, contains('skipped={unsupported-protocol:1}'));
  expect(summary, isNot(contains('secret')));
  expect(summary, isNot(contains('a.example')));
});
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`flutter test test/subscription_parse_diagnostics_test.dart`

预期：失败，当前没有解析统计行。

- [ ] **步骤 3：实现最小统计逻辑**

为 Clash YAML 解析构建源类型计数、接受类型计数和跳过类型计数；使用内容字节长度及非加密短哈希作为同一正文比对标识；只输出类型和数量，不输出节点字段。

- [ ] **步骤 4：运行测试并确认通过**

运行：`flutter test test/subscription_parse_diagnostics_test.dart test/subscription_tolerance_test.dart`

预期：通过。

- [ ] **步骤 5：更新项目总结并提交**

```powershell
git add lib/core/subscription.dart test/subscription_parse_diagnostics_test.dart PROJECT_SUMMARY.md
git commit -m "feat: report safe Clash parse diagnostics"
```

### 任务 6：全量验证与发布准备

**文件：**
- 修改：`PROJECT_SUMMARY.md`

- [ ] **步骤 1：执行针对性测试**

运行：

```powershell
flutter test test/hysteria2_support_test.dart test/hysteria_support_test.dart test/anytls_clash_support_test.dart test/subscription_parse_diagnostics_test.dart
```

预期：全部通过。

- [ ] **步骤 2：执行完整验证**

运行：

```powershell
flutter test
flutter analyze
```

预期：全部通过，且无分析警告。

- [ ] **步骤 3：记录版本迭代并提交**

在 `PROJECT_SUMMARY.md` 增加中文迭代记录，说明三端共享的 Clash Hysteria / AnyTLS 兼容修复和诊断能力；提交该记录。

