import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/node_health.dart' as health;
import 'package:forge_vpn_flutter/providers/app_provider.dart';

VpnNode _node(String id) => VpnNode(
      id: id,
      type: NodeType.vmess,
      name: id,
      server: '$id.example.com',
      port: 443,
      uuid: '11111111-1111-1111-1111-${id.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}',
    );

const _tcpAvailable = health.HealthCheckResult(
  ok: true,
  latency: 10,
  healthStatus: 'available',
  target: 'Node',
);

const _available = health.HealthCheckResult(
  ok: true,
  latency: 30,
  healthStatus: 'available',
  target: 'HTTPS',
);

const _unavailable = health.HealthCheckResult(
  ok: false,
  healthStatus: 'unavailable',
  target: 'HTTPS',
  error: '不可用',
);

Future<void> _flushAsyncWork([int turns = 10]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('导入新订阅会在请求开始前取消旧筛查', () async {
    final oldTcp = Completer<health.HealthCheckResult>();
    final requestCheckingStates = <bool>[];
    var requestCount = 0;
    late AppProvider provider;

    provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async {
        requestCheckingStates.add(provider.runtime.checkingNodes);
        requestCount++;
        return [_node(requestCount == 1 ? 'old' : 'new')];
      },
      tcpChecker: (node) {
        if (node.id == 'old') return oldTcp.future;
        return Future.value(_unavailable);
      },
      fullChecker: (node, corePath, runtimeDir) async => _available,
    );

    await provider.importSubscription('https://example.com/first');
    await _flushAsyncWork();
    expect(provider.runtime.checkingNodes, isTrue);

    await provider.importSubscription('https://example.com/second');
    expect(requestCheckingStates, [false, false]);

    oldTcp.complete(_tcpAvailable);
    await _flushAsyncWork();

    expect(provider.nodes.map((node) => node.id), ['new']);
  });

  test('停止检查会保留已完成结果并把未完成节点恢复为未检查', () async {
    final first = Completer<health.HealthCheckResult>();
    final second = Completer<health.HealthCheckResult>();
    final nodeA = _node('node-a');
    final nodeB = _node('node-b');

    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [nodeA, nodeB],
      tcpChecker: (node) async => _tcpAvailable,
      fullChecker: (node, corePath, runtimeDir) {
        return node.id == nodeA.id ? first.future : second.future;
      },
    );

    await provider.importSubscription('https://example.com/sub');
    await _flushAsyncWork();
    first.complete(_available);
    await _flushAsyncWork();

    expect(
      provider.nodes.singleWhere((node) => node.id == nodeA.id).healthStatus,
      HealthStatus.available,
    );
    expect(provider.runtime.checkingNodes, isTrue);

    provider.stopNodeChecks();
    second.complete(_unavailable);
    await _flushAsyncWork();

    expect(provider.runtime.checkingNodes, isFalse);
    expect(
      provider.nodes.singleWhere((node) => node.id == nodeA.id).healthStatus,
      HealthStatus.available,
    );
    expect(
      provider.nodes.singleWhere((node) => node.id == nodeB.id).healthStatus,
      HealthStatus.unknown,
    );
  });
}
