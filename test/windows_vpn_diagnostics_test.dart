import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/providers/app_provider.dart';

void main() {
  test('Windows 诊断在控制器尚未初始化时返回桌面状态', () async {
    final provider = AppProvider();

    final result = await provider.diagnoseVpn();

    expect(result['platform'], 'windows');
    expect(result['error'], 'controller unavailable');
  });
}
