import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forge_vpn_flutter/core/dns_fallback_coordinator.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/remote_dns.dart';
import 'package:forge_vpn_flutter/providers/app_provider.dart';

const _node = VpnNode(
  id: 'dns-node',
  type: NodeType.vmess,
  name: 'DNS node',
  server: 'node.example.com',
  port: 443,
  uuid: '11111111-1111-1111-1111-111111111111',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('恢复上次验证成功的远程 DNS', () async {
    SharedPreferences.setMockInitialValues({
      'remote_dns_provider': 'google',
    });
    final provider = AppProvider();

    await provider.restorePersistedState();

    expect(provider.preferredRemoteDns, RemoteDnsProvider.google);
  });

  test('首组失败后停止旧连接并持久化第二组成功结果', () async {
    final starts = <RemoteDnsProvider>[];
    var stops = 0;
    var probes = 0;
    final provider = AppProvider(
      connectionAttemptStarter: (node, settings, dns) async {
        expect(node.name, _node.name);
        expect(node.server, _node.server);
        expect(node.port, _node.port);
        expect(settings.routeMode, 'global');
        starts.add(dns);
      },
      connectionAttemptStopper: () async => stops++,
      connectionVerifier: () async => ++probes == 1
          ? const DnsAttemptResult.failed('polluted DNS')
          : const DnsAttemptResult.passed(statusCode: 204),
    );
    await provider.importSubscriptionText(
      '[{"type":"vmess","name":"DNS node","server":"node.example.com",'
      '"port":443,"id":"11111111-1111-1111-1111-111111111111"}]',
    );

    await provider.connect();

    expect(starts, [
      RemoteDnsProvider.cloudflare,
      RemoteDnsProvider.google,
    ]);
    expect(stops, 1);
    expect(provider.runtime.connected, isTrue);
    expect(provider.preferredRemoteDns, RemoteDnsProvider.google);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remote_dns_provider'), 'google');
    expect(
      provider.runtime.logs,
      contains('[dns-fallback] switching Cloudflare -> Google'),
    );
  });

  test('用户断开会取消正在等待的验证且不再切换下一组', () async {
    final probe = Completer<DnsAttemptResult>();
    final starts = <RemoteDnsProvider>[];
    var stops = 0;
    final provider = AppProvider(
      connectionAttemptStarter: (node, settings, dns) async {
        starts.add(dns);
      },
      connectionAttemptStopper: () async => stops++,
      connectionVerifier: () => probe.future,
    );
    await provider.importSubscriptionText(
      '[{"type":"vmess","name":"DNS node","server":"node.example.com",'
      '"port":443,"id":"11111111-1111-1111-1111-111111111111"}]',
    );

    final connection = provider.connect();
    await Future<void>.delayed(Duration.zero);
    await provider.disconnect();
    probe.complete(const DnsAttemptResult.failed('late failure'));

    await expectLater(connection, throwsA(isA<DnsFallbackCancelled>()));
    expect(starts, [RemoteDnsProvider.cloudflare]);
    expect(stops, 1);
    expect(provider.runtime.connected, isFalse);
  });

  test('三组全部失败时保持未连接并显示统一错误', () async {
    final provider = AppProvider(
      connectionAttemptStarter: (node, settings, dns) async {},
      connectionAttemptStopper: () async {},
      connectionVerifier: () async =>
          const DnsAttemptResult.failed('network failed'),
    );
    await provider.importSubscriptionText(
      '[{"type":"vmess","name":"DNS node","server":"node.example.com",'
      '"port":443,"id":"11111111-1111-1111-1111-111111111111"}]',
    );

    await expectLater(provider.connect(), throwsA(isA<AllDnsProvidersFailed>()));

    expect(provider.runtime.connected, isFalse);
    expect(
      provider.runtime.proxyWarning,
      '三组远程 DNS/代理链路均不可用，请检查节点或网络',
    );
  });
}
