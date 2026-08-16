import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

void main() {
  test('Clash 解析诊断按类型统计且不泄露凭据', () {
    final diagnostics = <String>[];

    parseSubscription('''
proxies:
  - name: supported
    type: anytls
    server: a.example
    port: 443
    password: secret
  - name: skipped
    type: unsupported-protocol
    server: b.example
    port: 443
''', onDiagnostic: diagnostics.add);

    final summary = diagnostics.singleWhere(
      (message) => message.startsWith('subscription parse summary:'),
    );
    expect(summary, contains('source={anytls:1, unsupported-protocol:1}'));
    expect(summary, contains('accepted={anytls:1}'));
    expect(summary, contains('skipped={unsupported-protocol:1}'));
    expect(summary, isNot(contains('secret')));
    expect(summary, isNot(contains('a.example')));
  });
}
