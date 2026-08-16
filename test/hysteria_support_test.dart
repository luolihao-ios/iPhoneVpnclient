import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

void main() {
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

    final outbound = (buildSingBoxConfig(node: node, includeSocks: false)
        ['outbounds'] as List)
      .first as Map<String, dynamic>;

    expect(node.type, NodeType.hysteria);
    expect(node.password, 'client-auth');
    expect(node.serverPorts, ['6000:11000']);
    expect(outbound['type'], 'hysteria');
    expect(outbound['auth_str'], 'client-auth');
    expect(outbound['obfs'], 'obfs-password');
    expect(outbound['server_ports'], ['6000:11000']);
  });
}
