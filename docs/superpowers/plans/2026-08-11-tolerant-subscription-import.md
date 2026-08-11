# 容错订阅导入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Forge VPN 导入免费订阅时容忍未编码 Unicode 名称和单条损坏节点，并验证纯文本、Base64、Clash YAML、sing-box JSON 四种入口。

**Architecture:** 在 `subscription.dart` 内增加安全名称解码与逐行故障隔离，不改变公开节点模型和现有结构化解析器。`parseSubscription` 保持现有返回类型，新增可选诊断回调，将成功数和跳过数传给现有下载日志链路。

**Tech Stack:** Dart 3.12、Flutter test、package:http、package:yaml。

## Global Constraints

- 保留当前工作区尚未提交的 sing-box JSON 解析和订阅诊断修改。
- 不修改节点健康检查、节点数量筛选、Windows UI 或 sing-box 核心版本。
- 不记录密码、UUID、私钥、完整节点 URI 或订阅查询参数。
- 单个 URI 节点失败不得中止整份订阅；最终无可用节点时维持现有空结果/错误行为。

---

### Task 1: 固定非标准节点名称和逐行隔离行为

**Files:**
- Create: `test/subscription_tolerance_test.dart`
- Test: `test/subscription_tolerance_test.dart`

**Interfaces:**
- Consumes: `List<VpnNode> parseSubscription(String rawText, {void Function(String message)? onDiagnostic})`
- Produces: 五个独立回归用例，覆盖 Unicode、合法编码、损坏编码、坏节点隔离和 Base64 包装。

- [ ] **Step 1: 写入未编码 Unicode 名称的失败测试**

```dart
test('keeps an unescaped Unicode Shadowsocks node name', () {
  final node = parseSubscription(
    'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US 🇺🇸 | @Raydikalx | FEA075',
  ).single;

  expect(node.name, 'US 🇺🇸 | @Raydikalx | FEA075');
  expect(node.type, NodeType.shadowsocks);
});
```

- [ ] **Step 2: 写入合法和损坏百分号编码的失败测试**

```dart
test('decodes valid percent escapes in a node name', () {
  final node = parseSubscription(
    'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US%20Node',
  ).single;
  expect(node.name, 'US Node');
});

test('keeps a malformed percent-encoded node name', () {
  final node = parseSubscription(
    'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US%ZZ Node',
  ).single;
  expect(node.name, 'US%ZZ Node');
});
```

- [ ] **Step 3: 写入单条坏节点隔离和 Base64 包装的失败测试**

```dart
test('skips one malformed URI and keeps following valid nodes', () {
  final diagnostics = <String>[];
  final nodes = parseSubscription(
    'vless://bad%ZZ\n'
    'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US 🇺🇸',
    onDiagnostic: diagnostics.add,
  );

  expect(nodes, hasLength(1));
  expect(diagnostics, contains('subscription URI parsing: parsed=1 skipped=1'));
});

test('applies tolerant URI parsing after Base64 decoding', () {
  final raw =
      'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US 🇺🇸';
  final encoded = base64.encode(utf8.encode(raw));
  expect(parseSubscription(encoded).single.name, 'US 🇺🇸');
});
```

- [ ] **Step 4: 运行测试并确认以预期原因失败**

Run:

```powershell
flutter test test/subscription_tolerance_test.dart
```

Expected: FAIL；未编码 Unicode 在 `_parseSsUri` 抛出 `Illegal percent encoding in URI`，且 `parseSubscription` 尚不接受 `onDiagnostic`。

### Task 2: 实现安全名称解码和逐行故障隔离

**Files:**
- Modify: `lib/core/subscription.dart:343-458,505-548`
- Test: `test/subscription_tolerance_test.dart`

**Interfaces:**
- Produces: `parseSubscription(String rawText, {void Function(String message)? onDiagnostic})`
- Produces: 私有 `_decodeNodeName(String rawName)` 与 `_parseUriLines(String text, {void Function(String message)? onDiagnostic})`
- Consumes: 现有 `_parseLine(String line)`、`_dedupeNodes` 和 `_filterSubscriptionMetadata`。

- [ ] **Step 1: 增加安全名称解码器**

```dart
String _decodeNodeName(String rawName) {
  if (!rawName.contains('%')) return rawName;
  try {
    return Uri.decodeComponent(rawName);
  } on FormatException {
    return rawName;
  } on ArgumentError {
    return rawName;
  }
}
```

在 `_parseSsUri` 中使用第一个 `#` 的位置分割主体和名称，避免名称内额外的 `#` 被丢弃：

```dart
final fragmentIndex = withoutScheme.indexOf('#');
final main = fragmentIndex >= 0
    ? withoutScheme.substring(0, fragmentIndex)
    : withoutScheme;
final rawName = fragmentIndex >= 0
    ? withoutScheme.substring(fragmentIndex + 1)
    : 'Shadowsocks';
final decodedName = _decodeNodeName(rawName);
```

- [ ] **Step 2: 增加逐行隔离解析器**

```dart
List<VpnNode> _parseUriLines(
  String text, {
  void Function(String message)? onDiagnostic,
}) {
  final nodes = <VpnNode>[];
  var skipped = 0;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    try {
      final node = _parseLine(line);
      if (node != null && node.isUsable) nodes.add(node);
    } catch (_) {
      skipped++;
    }
  }
  onDiagnostic?.call(
    'subscription URI parsing: parsed=${nodes.length} skipped=$skipped',
  );
  return nodes;
}
```

- [ ] **Step 3: 将容错解析接入 `parseSubscription` 和下载诊断**

```dart
List<VpnNode> parseSubscription(
  String rawText, {
  void Function(String message)? onDiagnostic,
}) {
  // 保留现有 JSON、YAML 和 Base64 识别流程。
  final nodes = _parseUriLines(
    decoded.isNotEmpty ? decoded : source,
    onDiagnostic: onDiagnostic,
  );
  return _dedupeNodes(_filterSubscriptionMetadata(nodes));
}
```

`fetchSubscription` 调用时传入已有的诊断回调：

```dart
final nodes = parseSubscription(body, onDiagnostic: onDiagnostic);
```

- [ ] **Step 4: 运行容错测试并确认通过**

Run:

```powershell
flutter test test/subscription_tolerance_test.dart
```

Expected: `All tests passed!`

### Task 3: 验证四类订阅入口和静态分析

**Files:**
- Modify only if a regression is found: `lib/core/subscription.dart`
- Test: `test/anytls_support_test.dart`
- Test: `test/subscription_tolerance_test.dart`

**Interfaces:**
- Consumes: Task 2 的容错 URI 解析接口和当前工作区的 sing-box JSON 解析器。
- Produces: 纯文本、Base64、Clash YAML、sing-box JSON 的完整回归证据。

- [ ] **Step 1: 运行两组订阅测试**

Run:

```powershell
flutter test test/subscription_tolerance_test.dart test/anytls_support_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 2: 运行相关文件静态分析**

Run:

```powershell
flutter analyze lib/core/subscription.dart lib/providers/app_provider.dart test/subscription_tolerance_test.dart test/anytls_support_test.dart
```

Expected: `No issues found!`

- [ ] **Step 3: 检查格式和差异**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib/core/subscription.dart test/subscription_tolerance_test.dart test/anytls_support_test.dart
git diff --check
```

Expected: 两条命令退出码均为 0，无尾随空格、格式错误或敏感订阅内容进入差异。

- [ ] **Step 4: 提交实现**

```powershell
git add lib/core/subscription.dart lib/providers/app_provider.dart test/anytls_support_test.dart test/subscription_tolerance_test.dart
git commit -m "fix: tolerate nonstandard subscription node names"
```

