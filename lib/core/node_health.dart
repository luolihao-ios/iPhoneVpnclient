import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models/node.dart';
import 'singbox_config.dart';

/// Result of a node health check.
class HealthCheckResult {
  final bool ok;
  final int? latency;
  final String healthStatus;
  final String target;
  final String? error;

  const HealthCheckResult({
    required this.ok,
    this.latency,
    this.healthStatus = 'unknown',
    this.target = 'YouTube',
    this.error,
  });
}

/// Perform a TCP ping to check if a host:port is reachable.
Future<int?> tcpPing(String host, int port, {int timeoutMs = 3000}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final addresses = await InternetAddress.lookup(
      host,
      type: InternetAddressType.IPv4,
    );
    if (addresses.isEmpty) return null;
    final socket = await Socket.connect(
      addresses.first,
      port,
      timeout: Duration(milliseconds: timeoutMs),
    );
    await socket.close();
    stopwatch.stop();
    return max(1, stopwatch.elapsedMilliseconds);
  } catch (_) {
    return null;
  }
}

/// Check a node from a mobile build without starting a local sing-box process.
Future<HealthCheckResult> checkNodeTcpAvailability({
  required VpnNode node,
  int timeoutMs = 3000,
}) async {
  final latency = await tcpPing(node.server, node.port, timeoutMs: timeoutMs);
  if (latency != null) {
    return HealthCheckResult(
      ok: true,
      latency: latency,
      healthStatus: 'available',
      target: 'Node',
    );
  }
  return const HealthCheckResult(
    ok: false,
    healthStatus: 'unavailable',
    target: 'Node',
    error: 'TCP connection timed out',
  );
}

/// Check a desktop node by establishing a real HTTP proxy tunnel through it.
Future<HealthCheckResult> checkNodeAvailability({
  required String corePath,
  required String runtimeDir,
  required VpnNode node,
  int timeoutMs = 3000,
  String targetHost = 'www.youtube.com',
  int targetPort = 443,
  String targetLabel = 'YouTube',
}) async {
  Process? child;
  String? configPath;
  final stopwatch = Stopwatch()..start();

  int remainingMs() => max(0, timeoutMs - stopwatch.elapsedMilliseconds);

  try {
    final dir = Directory(runtimeDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final httpPort = await _freePort();
    configPath =
        '${runtimeDir}/health-${pid}-${DateTime.now().millisecondsSinceEpoch}-${Random().nextDouble().toStringAsFixed(10)}.json';

    final config = buildSingBoxConfig(
      node: node,
      mode: 'global',
      tunEnabled: false,
      httpPort: httpPort,
      includeSocks: false,
      includeApi: false,
      cacheFile: false,
      logLevel: 'warn',
    );
    await File(configPath).writeAsString(singBoxConfigToJson(config));

    child = await Process.start(
      corePath,
      ['run', '-c', configPath],
      mode: ProcessStartMode.normal,
    );
    child.stdout.drain();
    child.stderr.drain();

    await _waitForLocalPort(httpPort, min(1200, remainingMs()));
    final response = await _probeHttpConnect(
      proxyPort: httpPort,
      targetHost: targetHost,
      targetPort: targetPort,
      timeoutMs: remainingMs(),
    );
    if (!isHttpProxyConnectEstablished(response)) {
      throw Exception('proxy CONNECT failed: ${response.trim()}');
    }

    return HealthCheckResult(
      ok: true,
      latency: max(1, stopwatch.elapsedMilliseconds),
      healthStatus: 'available',
      target: targetLabel,
    );
  } catch (error) {
    return HealthCheckResult(
      ok: false,
      healthStatus: 'unavailable',
      target: targetLabel,
      error: error.toString().length > 160
          ? error.toString().substring(0, 160)
          : error.toString(),
    );
  } finally {
    child?.kill();
    if (configPath != null) {
      try {
        await File(configPath).delete();
      } catch (_) {}
    }
  }
}

/// Whether an HTTP proxy confirmed that it established the requested tunnel.
bool isHttpProxyConnectEstablished(String response) {
  return RegExp(r'^HTTP/1\.[01] 200\b', caseSensitive: false)
      .hasMatch(response.trimLeft());
}

Future<String> _probeHttpConnect({
  required int proxyPort,
  required String targetHost,
  required int targetPort,
  required int timeoutMs,
}) async {
  if (timeoutMs <= 0) throw TimeoutException('node check timed out');
  Socket? socket;
  try {
    socket = await Socket.connect(
      '127.0.0.1',
      proxyPort,
      timeout: Duration(milliseconds: timeoutMs),
    );
    socket.write(
      'CONNECT $targetHost:$targetPort HTTP/1.1\r\n'
      'Host: $targetHost:$targetPort\r\n'
      'Proxy-Connection: close\r\n\r\n',
    );
    await socket.flush();
    return await utf8
        .decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first
        .timeout(Duration(milliseconds: timeoutMs));
  } finally {
    socket?.destroy();
  }
}

Future<int> _freePort() async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final port = server.port;
  await server.close();
  return port;
}

Future<void> _waitForLocalPort(int port, int timeoutMs) async {
  if (timeoutMs <= 0) throw TimeoutException('health proxy did not start');
  final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
  while (DateTime.now().millisecondsSinceEpoch < deadline) {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 250),
      );
      await socket.close();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  throw Exception('health proxy did not start');
}
