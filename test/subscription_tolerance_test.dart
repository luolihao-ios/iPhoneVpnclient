import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

const _ssPrefix = 'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443';

void main() {
  test('未转义的 Unicode Shadowsocks 节点名称会原样保留', () {
    final node = parseSubscription(
      '$_ssPrefix#US 🇺🇸 | @Raydikalx | FEA075',
    ).single;

    expect(node.name, 'US 🇺🇸 | @Raydikalx | FEA075');
    expect(node.type, NodeType.shadowsocks);
  });

  test('合法百分号编码的节点名称会被解码', () {
    final node = parseSubscription('$_ssPrefix#US%20Node').single;

    expect(node.name, 'US Node');
  });

  test('损坏的百分号编码节点名称会保留原文', () {
    final node = parseSubscription('$_ssPrefix#US%ZZ Node').single;

    expect(node.name, 'US%ZZ Node');
  });

  test('单条损坏 URI 会被跳过并保留后续有效节点', () {
    final diagnostics = <String>[];
    final nodes = parseSubscription(
      'vless://bad%ZZ\n$_ssPrefix#US 🇺🇸',
      onDiagnostic: diagnostics.add,
    );

    expect(nodes, hasLength(1));
    expect(
      diagnostics,
      contains('subscription URI parsing: parsed=1 skipped=1'),
    );
  });

  test('Base64 解码后仍使用容错 URI 解析', () {
    final raw = '$_ssPrefix#US 🇺🇸';
    final encoded = base64.encode(utf8.encode(raw));

    expect(parseSubscription(encoded).single.name, 'US 🇺🇸');
  });
}
