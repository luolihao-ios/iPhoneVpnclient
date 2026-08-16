import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';

void main() {
  const node = VpnNode(
    id: 'health-node',
    name: 'Health node',
    type: NodeType.vmess,
    server: 'node.example.com',
    port: 443,
    uuid: '00000000-0000-0000-0000-000000000001',
  );

  test('健康检查配置只把流量发往候选节点', () {
    final config = buildSingBoxHealthCheckConfig(node: node, httpPort: 19080);
    final inbounds = config['inbounds'] as List<dynamic>;
    final outbounds = config['outbounds'] as List<dynamic>;

    expect(
      inbounds,
      contains(predicate((entry) =>
          entry is Map<String, dynamic> &&
          entry['type'] == 'http' &&
          entry['listen'] == '127.0.0.1' &&
          entry['listen_port'] == 19080)),
    );
    expect(
      outbounds,
      contains(predicate((entry) =>
          entry is Map<String, dynamic> && entry['tag'] == 'health-proxy')),
    );
    expect((config['route'] as Map<String, dynamic>)['final'], 'health-proxy');
    expect(config.containsKey('experimental'), isFalse);
  });

  test('移动端配置保留所有节点并通过选择器路由', () {
    const alternate = VpnNode(
      id: 'alternate-node',
      name: 'Alternate node',
      type: NodeType.vless,
      server: 'alternate.example.com',
      port: 443,
      uuid: '00000000-0000-0000-0000-000000000002',
    );
    final config = buildSingBoxConfig(
      node: node,
      nodes: const [node, alternate],
      mode: 'global',
      tunEnabled: true,
    );
    final outbounds = config['outbounds'] as List<dynamic>;
    final selector = outbounds.cast<Map<String, dynamic>>().singleWhere(
          (outbound) => outbound['tag'] == 'proxy',
        );

    expect(selector['type'], 'selector');
    expect(selector['outbounds'], ['node-health-node', 'node-alternate-node']);
    expect(selector['default'], 'node-health-node');
    expect(
      outbounds.whereType<Map<String, dynamic>>().map((outbound) => outbound['tag']),
      containsAll(['node-health-node', 'node-alternate-node']),
    );
  });
}
