import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/log_export.dart';

void main() {
  test('日志导出写入 UTF-8 文本和 Forge VPN 标题', () async {
    final directory =
        await Directory.systemTemp.createTemp('forge-vpn-log-test-');
    addTearDown(() => directory.delete(recursive: true));

    final file = await writeLogExport(
      directory: directory,
      logs: const ['VPN connected', 'latency: 32 ms'],
      now: DateTime(2026, 7, 26, 9, 8, 7),
    );

    expect(file.path, endsWith('ForgeVPN-20260726-090807.txt'));
    expect(await file.readAsString(), contains('Forge VPN 日志'));
    expect(await file.readAsString(), contains('VPN connected'));
    expect(await file.readAsString(), contains('latency: 32 ms'));
  });
}
