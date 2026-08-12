import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/dns_fallback_coordinator.dart';
import 'package:forge_vpn_flutter/core/remote_dns.dart';

void main() {
  test('第一组验证成功后保留连接且不再尝试其他解析器', () async {
    final events = <String>[];
    final coordinator = DnsFallbackCoordinator(onLog: events.add);

    final selected = await coordinator.connect(
      preferred: null,
      start: (provider) async => events.add('start:${provider.name}'),
      stop: () async => events.add('stop'),
      verify: () async => const DnsAttemptResult.passed(statusCode: 204),
    );

    expect(selected, RemoteDnsProvider.cloudflare);
    expect(events.where((event) => event.startsWith('start:')), [
      'start:cloudflare',
    ]);
    expect(events, isNot(contains('stop')));
  });

  test('第一组失败后先停止并切换到第二组', () async {
    final events = <String>[];
    var probes = 0;
    final coordinator = DnsFallbackCoordinator(onLog: events.add);

    final selected = await coordinator.connect(
      preferred: RemoteDnsProvider.cloudflare,
      start: (provider) async => events.add('start:${provider.name}'),
      stop: () async => events.add('stop'),
      verify: () async => ++probes == 1
          ? const DnsAttemptResult.failed('timeout')
          : const DnsAttemptResult.passed(statusCode: 204),
    );

    expect(selected, RemoteDnsProvider.google);
    expect(
      events.where(
        (event) => event == 'stop' || event.startsWith('start:'),
      ),
      ['start:cloudflare', 'stop', 'start:google'],
    );
    expect(
      events,
      contains('[dns-fallback] switching Cloudflare -> Google'),
    );
  });

  test('三组全部失败时每组都停止并返回统一错误', () async {
    final starts = <RemoteDnsProvider>[];
    var stops = 0;
    final coordinator = DnsFallbackCoordinator();

    await expectLater(
      coordinator.connect(
        preferred: RemoteDnsProvider.google,
        start: (provider) async => starts.add(provider),
        stop: () async => stops++,
        verify: () async => const DnsAttemptResult.failed('network failed'),
      ),
      throwsA(
        isA<AllDnsProvidersFailed>().having(
          (error) => error.message,
          'message',
          '三组远程 DNS/代理链路均不可用，请检查节点或网络',
        ),
      ),
    );

    expect(starts, [
      RemoteDnsProvider.google,
      RemoteDnsProvider.quad9,
      RemoteDnsProvider.cloudflare,
    ]);
    expect(stops, 3);
  });

  test('取消当前序列后不再启动下一组解析器', () async {
    final firstProbe = Completer<DnsAttemptResult>();
    final starts = <RemoteDnsProvider>[];
    final coordinator = DnsFallbackCoordinator();

    final connection = coordinator.connect(
      preferred: null,
      start: (provider) async => starts.add(provider),
      stop: () async {},
      verify: () => firstProbe.future,
    );
    await Future<void>.delayed(Duration.zero);

    coordinator.cancel();
    firstProbe.complete(const DnsAttemptResult.failed('late failure'));

    await expectLater(connection, throwsA(isA<DnsFallbackCancelled>()));
    expect(starts, [RemoteDnsProvider.cloudflare]);
  });

  test('启动解析器本身失败也会停止并尝试下一组', () async {
    final events = <String>[];
    var starts = 0;
    final coordinator = DnsFallbackCoordinator(onLog: events.add);

    final selected = await coordinator.connect(
      preferred: null,
      start: (provider) async {
        starts++;
        events.add('start:${provider.name}');
        if (starts == 1) throw Exception('start failed');
      },
      stop: () async => events.add('stop'),
      verify: () async => const DnsAttemptResult.passed(statusCode: 204),
    );

    expect(selected, RemoteDnsProvider.google);
    expect(
      events.where(
        (event) => event == 'stop' || event.startsWith('start:'),
      ),
      ['start:cloudflare', 'stop', 'start:google'],
    );
  });
}
