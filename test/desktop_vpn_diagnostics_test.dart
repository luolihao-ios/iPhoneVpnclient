import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/desktop_vpn_diagnostics.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';
import 'package:forge_vpn_flutter/services/singbox_service.dart';

void main() {
  test('桌面诊断报告核心、配置、运行状态和端口', () async {
    final directory =
        await Directory.systemTemp.createTemp('forge-vpn-diagnostics-');
    addTearDown(() => directory.delete(recursive: true));
    final core = File('${directory.path}${Platform.pathSeparator}sing-box.exe')
      ..createSync();
    final config =
        File('${directory.path}${Platform.pathSeparator}sing-box.json')
          ..createSync();

    final result = await collectDesktopVpnDiagnostics(
      corePath: core.path,
      snapshot: SingBoxRuntimeSnapshot(
        running: true,
        pid: 4242,
        startedAt: DateTime.utc(2026, 7, 30),
        configPath: config.path,
        recentLogs: const ['INFO started'],
      ),
      isPortListening: (port) async => port == defaultHttpPort,
    );

    expect(result['platform'], 'windows');
    expect(result['coreExists'], isTrue);
    expect(result['configExists'], isTrue);
    expect(result['running'], isTrue);
    expect(result['pid'], 4242);
    expect(result['httpPortListening'], isTrue);
    expect(result['socksPortListening'], isFalse);
    expect(result['apiPortListening'], isFalse);
    expect(result['recentLogs'], const ['INFO started']);
  });
}
