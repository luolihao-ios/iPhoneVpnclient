import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

void main() {
  test('parses a Hysteria2 node from Clash YAML', () {
    final nodes = parseSubscription('''
proxies:
  - name: Hysteria2 Clash
    type: hysteria2
    server: hy2.example.com
    port: 8443
    password: client-password
    sni: cdn.example.com
    alpn: [h3, h2]
    skip-cert-verify: true
    obfs: obfs-password
    up: 20
    down: 100
''');

    expect(nodes, hasLength(1));
    final node = nodes.single;
    expect(node.type, NodeType.hysteria2);
    expect(node.server, 'hy2.example.com');
    expect(node.port, 8443);
    expect(node.password, 'client-password');
    expect(node.serverName, 'cdn.example.com');
    expect(node.alpn, ['h3', 'h2']);
    expect(node.insecure, isTrue);
    expect(node.obfs, 'obfs-password');
    expect(node.upMbps, 20);
    expect(node.downMbps, 100);
  });

  test('parses a Hysteria2 sing-box outbound', () {
    final nodes = parseSubscription(jsonEncode({
      'outbounds': [
        {
          'type': 'hysteria2',
          'tag': 'Hysteria2 sing-box',
          'server': 'hy2.example.com',
          'server_port': 443,
          'password': 'client-password',
          'up_mbps': 30,
          'down_mbps': 150,
          'obfs': {'type': 'salamander', 'password': 'obfs-password'},
          'tls': {
            'enabled': true,
            'server_name': 'cdn.example.com',
            'insecure': true,
            'alpn': ['h3'],
          },
        },
      ],
    }));

    final node = nodes.single;
    expect(node.type, NodeType.hysteria2);
    expect(node.name, 'Hysteria2 sing-box');
    expect(node.serverName, 'cdn.example.com');
    expect(node.alpn, ['h3']);
    expect(node.obfs, 'obfs-password');
    expect(node.upMbps, 30);
    expect(node.downMbps, 150);
  });

  test('persists Hysteria2 fields and emits a native sing-box outbound', () {
    const node = VpnNode(
      id: 'hy2-1',
      type: NodeType.hysteria2,
      name: 'Hysteria2',
      server: 'hy2.example.com',
      port: 443,
      password: 'client-password',
      tls: true,
      serverName: 'cdn.example.com',
      insecure: true,
      alpn: ['h3'],
      obfs: 'obfs-password',
      upMbps: 20,
      downMbps: 100,
    );

    final restored = VpnNode.fromJson(node.toJson());
    final outbound = (buildSingBoxConfig(
      node: restored,
      includeSocks: false,
    )['outbounds'] as List)
        .first as Map<String, dynamic>;

    expect(restored.alpn, ['h3']);
    expect(restored.obfs, 'obfs-password');
    expect(outbound['type'], 'hysteria2');
    expect(outbound['password'], 'client-password');
    expect(outbound['up_mbps'], 20);
    expect(outbound['down_mbps'], 100);
    expect(outbound['obfs'], {'type': 'salamander', 'password': 'obfs-password'});
    expect((outbound['tls'] as Map)['enabled'], isTrue);
    expect((outbound['tls'] as Map)['server_name'], 'cdn.example.com');
    expect((outbound['tls'] as Map)['alpn'], ['h3']);
  });
}
