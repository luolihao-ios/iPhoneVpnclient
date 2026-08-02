import 'dart:async';
import 'dart:io';

import '../services/singbox_service.dart';
import 'singbox_config.dart';

typedef PortListener = Future<bool> Function(int port);

Future<bool> isTcpPortListening(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 250),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

Future<Map<String, dynamic>> collectDesktopVpnDiagnostics({
  required String corePath,
  required SingBoxRuntimeSnapshot snapshot,
  PortListener isPortListening = isTcpPortListening,
}) async {
  final configPath = snapshot.configPath;
  final portStates = await Future.wait([
    isPortListening(defaultHttpPort),
    isPortListening(defaultSocksPort),
    isPortListening(defaultApiPort),
  ]);

  return {
    'platform': 'windows',
    'corePath': corePath,
    'coreExists': corePath.isNotEmpty && await File(corePath).exists(),
    'running': snapshot.running,
    'pid': snapshot.pid,
    'startedAt': snapshot.startedAt?.toIso8601String(),
    'configPath': configPath,
    'configExists': configPath != null && await File(configPath).exists(),
    'httpPortListening': portStates[0],
    'socksPortListening': portStates[1],
    'apiPortListening': portStates[2],
    'exitCode': snapshot.exitCode,
    'recentLogs': snapshot.recentLogs.length <= 20
        ? snapshot.recentLogs
        : snapshot.recentLogs.sublist(snapshot.recentLogs.length - 20),
  };
}
