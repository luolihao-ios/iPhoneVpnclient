import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/initial_node_screening.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/node_health.dart';

VpnNode _node(int index, {String? server, int? port}) => VpnNode(
      id: 'node-$index',
      type: NodeType.vmess,
      name: '节点 $index',
      server: server ?? 'server-$index.example.com',
      port: port ?? 443,
      uuid: '11111111-1111-1111-1111-${index.toString().padLeft(12, '0')}',
    );

const _available = HealthCheckResult(
  ok: true,
  latency: 30,
  healthStatus: 'available',
  target: 'HTTPS',
);

const _unavailable = HealthCheckResult(
  ok: false,
  healthStatus: 'unavailable',
  target: 'HTTPS',
  error: '不可用',
);

class _FakeClock {
  DateTime value = DateTime.utc(2026, 8, 11);

  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

void main() {
  test('TCP 预筛覆盖全部节点且只真实验证 TCP 可达节点', () async {
    final nodes = List.generate(4, _node);
    final tcpVisited = <String>[];
    final validated = <String>[];

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      tcpConcurrency: 2,
      validationConcurrency: 1,
      tcpProbe: (node) async {
        tcpVisited.add(node.id);
        return node.id == 'node-2' ? null : 20;
      },
      validate: (node) async {
        validated.add(node.id);
        return _available;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {},
      isCancelled: () => false,
    );

    expect(tcpVisited.toSet(), nodes.map((node) => node.id).toSet());
    expect(validated, isNot(contains('node-2')));
    expect(summary.tcpCheckedCount, 4);
    expect(summary.validatedCount, 3);
    expect(summary.availableCount, 3);
  });

  test('15 秒快速窗口内达到 5 个后仍继续保留可用结果', () async {
    final nodes = List.generate(12, _node);
    final clock = _FakeClock();

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      now: clock.now,
      quickWindow: const Duration(seconds: 15),
      overallLimit: const Duration(seconds: 45),
      validationConcurrency: 1,
      tcpProbe: (_) async => 10,
      validate: (_) async {
        clock.advance(const Duration(seconds: 2));
        return _available;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {},
      isCancelled: () => false,
    );

    expect(summary.availableCount, 8);
    expect(summary.validatedCount, 8);
    expect(summary.reachedMinimumAfterQuickWindow, isTrue);
  });

  test('15 秒后不足 5 个会继续检查直到获得 5 个', () async {
    final nodes = List.generate(12, _node);
    final clock = _FakeClock();
    var attempts = 0;

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      now: clock.now,
      quickWindow: const Duration(seconds: 15),
      overallLimit: const Duration(seconds: 45),
      validationConcurrency: 1,
      tcpProbe: (_) async => 10,
      validate: (_) async {
        attempts++;
        clock.advance(const Duration(seconds: 4));
        return attempts <= 4 ? _unavailable : _available;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {},
      isCancelled: () => false,
    );

    expect(summary.availableCount, 5);
    expect(summary.validatedCount, 9);
    expect(summary.timedOut, isFalse);
  });

  test('小型优质订阅在快速窗口内保留全部结果', () async {
    final nodes = List.generate(4, _node);
    final clock = _FakeClock();

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      now: clock.now,
      validationConcurrency: 1,
      tcpProbe: (_) async => 10,
      validate: (_) async {
        clock.advance(const Duration(seconds: 2));
        return _available;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {},
      isCancelled: () => false,
    );

    expect(summary.availableCount, 4);
    expect(summary.validatedCount, 4);
    expect(summary.exhaustedCandidates, isTrue);
  });

  test('45 秒总时限结束检查并保留已完成结果', () async {
    final nodes = List.generate(20, _node);
    final clock = _FakeClock();

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      now: clock.now,
      quickWindow: const Duration(seconds: 15),
      overallLimit: const Duration(seconds: 45),
      validationConcurrency: 1,
      tcpProbe: (_) async => 10,
      validate: (_) async {
        clock.advance(const Duration(seconds: 10));
        return _unavailable;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {},
      isCancelled: () => false,
    );

    expect(summary.validatedCount, 5);
    expect(summary.timedOut, isTrue);
  });

  test('取消后停止领取新的真实验证任务', () async {
    final nodes = List.generate(8, _node);
    var cancelled = false;

    final summary = await runInitialNodeScreening(
      nodes: nodes,
      validationConcurrency: 1,
      tcpProbe: (_) async => 10,
      validate: (_) async {
        return _available;
      },
      onNodeChecking: (_) {},
      onTcpReachable: (_, __) {},
      onNodeResult: (_, __) {
        cancelled = true;
      },
      isCancelled: () => cancelled,
    );

    expect(summary.cancelled, isTrue);
    expect(summary.validatedCount, 1);
  });
}
