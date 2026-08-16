import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

void main() {
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
}
