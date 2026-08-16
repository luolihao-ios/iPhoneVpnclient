import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 将节点检查转发给活动 sing-box 核心', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/forge_vpn_flutter/VpnBridge.kt',
    ).readAsStringSync();

    expect(source, contains('"checkNodeHealth"'));
    expect(source, contains('ForgeVpnService.checkNodeHealth'));
  });

  test('iOS Packet Tunnel 通过 Clash API 执行节点检查', () {
    final plugin = File('ios/Runner/VpnPlugin.swift').readAsStringSync();
    final provider = File(
      'ios/Runner/PacketTunnelProvider.swift',
    ).readAsStringSync();

    expect(plugin, contains('case "checkNodeHealth":'));
    expect(provider, contains('hasPrefix("health:")'));
    expect(provider, contains('/proxies/'));
    expect(provider, contains('/delay'));
    expect(provider, contains('URLQueryItem(name: "url"'));
  });

  test('移动端切换节点会请求核心 selector', () {
    final android = File(
      'android/app/src/main/kotlin/com/example/forge_vpn_flutter/LibboxServiceController.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/PacketTunnelProvider.swift').readAsStringSync();

    expect(android, contains('selectOutbound'));
    expect(android, contains('requestMethod = "PUT"'));
    expect(ios, contains('hasPrefix("select:")'));
    expect(ios, contains('httpMethod = "PUT"'));
  });
}
