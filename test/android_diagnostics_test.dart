import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/services/android_vpn_service.dart';

void main() {
  test('normalizes native diagnostics without losing interface details', () {
    final result = AndroidVpnService.normalizeDiagnostics({
      'status': 'connected',
      'permissionGranted': true,
      'serviceRunning': true,
      'tunEstablished': true,
      'commandServerReady': true,
      'defaultInterface': 'wlan0',
      'interfaces': [
        {'name': 'wlan0', 'type': 'wifi', 'mtu': 1500},
      ],
    });

    expect(result['status'], 'connected');
    expect(result['permissionGranted'], isTrue);
    expect(result['serviceRunning'], isTrue);
    expect(result['defaultInterface'], 'wlan0');
    expect(result['interfaces'], hasLength(1));
  });

  test('normalizes malformed native values to safe defaults', () {
    final result = AndroidVpnService.normalizeDiagnostics({
      'status': 42,
      'permissionGranted': 'yes',
      'interfaces': 'not-a-list',
    });

    expect(result['status'], 'idle');
    expect(result['permissionGranted'], isFalse);
    expect(result['interfaces'], isEmpty);
  });
}
