import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/services/singbox_service.dart';

void main() {
  test('运行快照保留最近日志并限制为最后 120 行', () {
    final logs = List.generate(125, (index) => 'line-$index');

    final snapshot = SingBoxRuntimeSnapshot(
      running: true,
      pid: 4242,
      recentLogs: logs,
    );

    expect(snapshot.running, isTrue);
    expect(snapshot.pid, 4242);
    expect(snapshot.recentLogs, hasLength(120));
    expect(snapshot.recentLogs.first, 'line-5');
    expect(snapshot.recentLogs.last, 'line-124');
  });

  test('核心在启动窗口退出时不报告已连接并保留退出码', () async {
    if (!Platform.isWindows) return;
    final directory =
        await Directory.systemTemp.createTemp('forge-vpn-startup-');
    addTearDown(() => directory.delete(recursive: true));
    final immediateExitCore = File(
      '${directory.path}${Platform.pathSeparator}immediate-exit.cmd',
    )..writeAsStringSync('@echo off\r\nexit /b 1\r\n');
    final stateChanges = <bool>[];
    final controller = SingBoxController(
      corePath: immediateExitCore.path,
      runtimeDir: directory.path,
      startupGracePeriod: const Duration(milliseconds: 50),
      onState: ({bool? connected, int? pid, int? code}) {
        stateChanges.add(connected ?? false);
      },
    );

    await expectLater(
      controller.connect(
        node: const VpnNode(
          id: 'test',
          name: 'test',
          type: NodeType.vmess,
          server: '127.0.0.1',
          port: 443,
        ),
      ),
      throwsA(isA<Exception>()),
    );

    expect(controller.snapshot.running, isFalse);
    expect(controller.snapshot.exitCode, isNotNull);
    expect(stateChanges, isNot(contains(true)));
  });

  test('Windows 正式连接禁用 cache.db 并使用本地 DNS', () async {
    if (!Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp('forge-vpn-dns-');
    addTearDown(() => directory.delete(recursive: true));
    final longRunningCore = File(
      '${directory.path}${Platform.pathSeparator}long-running.cmd',
    )..writeAsStringSync('@echo off\r\nping -n 6 127.0.0.1 >nul\r\n');
    final controller = SingBoxController(
      corePath: longRunningCore.path,
      runtimeDir: directory.path,
      startupGracePeriod: const Duration(milliseconds: 300),
    );
    addTearDown(controller.dispose);

    await controller.connect(
      node: const VpnNode(
        id: 'test',
        name: 'test',
        type: NodeType.vmess,
        server: '127.0.0.1',
        port: 443,
      ),
    );

    final config = jsonDecode(
      await File(controller.configPath!).readAsString(),
    ) as Map<String, dynamic>;
    expect((config['dns'] as Map)['final'], 'local');
    final experimental =
        (config['experimental'] as Map).cast<String, dynamic>();
    expect(experimental, isNot(contains('cache_file')));
  });
}
