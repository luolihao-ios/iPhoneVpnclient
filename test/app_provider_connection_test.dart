import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/providers/app_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _subscription =
    '[{"type":"vmess","name":"single connection","server":"node.example.com",'
    '"port":443,"id":"11111111-1111-1111-1111-111111111111"}]';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('正式连接只启动一次选中平台', () async {
    var starts = 0;
    final provider = AppProvider(
      connectionAttemptStarter: (node, settings) async {
        starts++;
        expect(node.name, 'single connection');
        expect(settings.routeMode, 'global');
      },
    );
    addTearDown(provider.dispose);
    await provider.importSubscriptionText(_subscription);

    await provider.connect();

    expect(starts, 1);
    expect(provider.runtime.connected, isTrue);
    expect(provider.runtime.proxyWarning, isEmpty);
  });

  test('正式连接失败后不重试也不报告已连接', () async {
    var starts = 0;
    final provider = AppProvider(
      connectionAttemptStarter: (node, settings) async {
        starts++;
        throw Exception('platform startup failed');
      },
    );
    addTearDown(provider.dispose);
    await provider.importSubscriptionText(_subscription);

    await expectLater(provider.connect(), throwsA(isA<Exception>()));

    expect(starts, 1);
    expect(provider.runtime.connected, isFalse);
    expect(provider.runtime.proxyWarning, isEmpty);
  });
}
