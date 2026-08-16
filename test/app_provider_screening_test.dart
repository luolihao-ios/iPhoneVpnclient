import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/node_health.dart' as health;
import 'package:forge_vpn_flutter/core/singbox_urltest.dart';
import 'package:forge_vpn_flutter/providers/app_provider.dart';

VpnNode _node(String id) => VpnNode(
      id: id,
      type: NodeType.vmess,
      name: id,
      server: '$id.example.com',
      port: 443,
      uuid:
          '11111111-1111-1111-1111-${id.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}',
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

class _FakeDesktopHealthSession implements DesktopNodeHealthSession {
  _FakeDesktopHealthSession(this.results);

  final Map<String, health.HealthCheckResult> results;
  final checkedNodeIds = <String>[];
  var closeCalls = 0;

  @override
  Future<health.HealthCheckResult> check(VpnNode node) async {
    checkedNodeIds.add(node.id);
    return results[node.id] ?? _unavailable;
  }

  @override
  Future<void> close() async {
    closeCalls++;
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

  test('注入移动端核心检查器时不会使用 TCP 连通性判断', () async {
    var tcpCalls = 0;
    var coreCalls = 0;
    final node = _node('mobile-node');
    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [node],
      tcpChecker: (_) async {
        tcpCalls++;
        return _tcpAvailable;
      },
      mobileHealthChecker: (_) async {
        coreCalls++;
        return _unavailable;
      },
    );

    await provider.importSubscription('https://example.com/sub');
    await _flushAsyncWork();
    await provider.pingNode(node.id);

    expect(coreCalls, greaterThan(0));
    expect(tcpCalls, 0);
    expect(provider.nodes.single.healthStatus, HealthStatus.unavailable);
  });

  test('移动端导入订阅会等待核心启动后再自动检查', () async {
    var coreCalls = 0;
    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [_node('mobile-node')],
      mobileHealthChecker: (_) async {
        coreCalls++;
        return _available;
      },
    );

    await provider.importSubscription('https://example.com/sub');
    await _flushAsyncWork();

    expect(coreCalls, 0);
    expect(provider.nodes.single.healthStatus, HealthStatus.unknown);
  });

  test('节点真实验证失败会记录不含敏感信息的诊断', () async {
    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [_node('failed-node')],
      tcpChecker: (_) async => _tcpAvailable,
      fullChecker: (_, __, ___) async => const health.HealthCheckResult(
        ok: false,
        healthStatus: 'unavailable',
        target: 'HTTPS 204',
        error: 'proxy CONNECT failed: HTTP/1.1 502 Bad Gateway',
      ),
    );

    await provider.importSubscription('https://example.com/sub');
    await _flushAsyncWork();

    expect(
      provider.runtime.logs,
      contains('node health failed: node=failed-node target=HTTPS 204 '
          'error=proxy CONNECT failed: HTTP/1.1 502 Bad Gateway'),
    );
  });

  test('Windows 全节点检查只启动一个原生 URLTest 会话', () async {
    final nodeA = _node('node-a');
    final nodeB = _node('node-b');
    final session = _FakeDesktopHealthSession({
      nodeA.id: _available,
      nodeB.id: _unavailable,
    });
    var sessionStarts = 0;
    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [nodeA, nodeB],
      desktopHealthSessionFactory: (nodes, corePath, runtimeDir) async {
        sessionStarts++;
        expect(nodes.map((node) => node.id), [nodeA.id, nodeB.id]);
        return session;
      },
    );

    await provider.importSubscription('https://example.com/sub');
    await _flushAsyncWork(30);

    expect(sessionStarts, 1);
    expect(session.checkedNodeIds.toSet(), {nodeA.id, nodeB.id});
    expect(session.closeCalls, 1);
    expect(
      provider.nodes.singleWhere((node) => node.id == nodeA.id).healthStatus,
      HealthStatus.available,
    );
    expect(
      provider.nodes.singleWhere((node) => node.id == nodeB.id).healthStatus,
      HealthStatus.unavailable,
    );
  });
}
