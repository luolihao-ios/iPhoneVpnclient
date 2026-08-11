import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/node_latency.dart';

void main() {
  test('重置节点健康状态会清除旧延迟和检查详情', () {
    const node = VpnNode(
      id: 'node-1',
      type: NodeType.vmess,
      name: '测试节点',
      server: 'example.com',
      port: 443,
      uuid: '11111111-1111-1111-1111-111111111111',
      healthStatus: HealthStatus.checking,
      latencyMs: 88,
      healthError: '旧错误',
      healthTarget: 'HTTPS',
      latencyCheckedAt: 123456,
    );

    final reset = resetNodeHealth(node);

    expect(reset.healthStatus, HealthStatus.unknown);
    expect(reset.latencyMs, isNull);
    expect(reset.healthError, isNull);
    expect(reset.healthTarget, isNull);
    expect(reset.latencyCheckedAt, isNull);
  });
}
