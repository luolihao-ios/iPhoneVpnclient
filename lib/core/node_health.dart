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
    // Android emulators often advertise IPv6 DNS answers without a working
    // IPv6 route. Prefer IPv4 so a healthy endpoint is not reported as down
    // before libbox gets a chance to establish the real protocol connection.
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
/// Android/iOS use the native libbox runtime, so there is no CLI executable for
/// the desktop-style health check path. A TCP probe still verifies that the
/// subscription endpoint is reachable and gives the user a useful latency.
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
  return HealthCheckResult(
    ok: false,
    healthStatus: 'unavailable',
    target: 'Node',
    error: 'TCP connection timed out',
  );
}

/// Check node availability by starting a sing-box instance and making a real request.
Future<HealthCheckResult> checkNodeAvailability({
  required String corePath,
  required String runtimeDir,
  required VpnNode node,
  int timeoutMs = 9000,
  String targetHost = 'www.gstatic.com',
  int targetPort = 443,
  String targetLabel = 'HTTPS',
}) async {
  Process? child;
  String? configPath;

  try {
    final dir = Directory(runtimeDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    // Find a free port
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

    final configFile = File(configPath);
    await configFile.writeAsString(singBoxConfigToJson(config));

    child = await Process.start(corePath, ['run', '-c', configPath],
        mode: ProcessStartMode.normal);
    child.stdout.drain();
    child.stderr.drain();

    await _waitForLocalPort(httpPort, min(2500, timeoutMs));
    final geo = await _probeForeignExitIp(httpPort, timeoutMs);

    if (!geo.isForeign) {
      throw Exception(geo.error ?? '出口 IP 位于中国或无法确认');
    }

    // Keep availability validation separate from the displayed latency. The
    // latter should match desktop clients: a direct TCP round-trip to the
    // node endpoint, not the much slower geo-IP HTTP request.
    final latency = await tcpPing(node.server, node.port, timeoutMs: timeoutMs);

    return HealthCheckResult(
      ok: true,
      latency: latency,
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

class _GeoProbeResult {
  const _GeoProbeResult(this.isForeign, {this.error});
  final bool isForeign;
  final String? error;
}

Future<_GeoProbeResult> _probeForeignExitIp(int proxyPort, int timeoutMs) async {
  const endpoints = [
    'https://api.ip.sb/geoip',
    'https://ipinfo.io/json',
    'https://ipapi.co/json/',
  ];
  final errors = <String>[];
  for (final endpoint in endpoints) {
    final result = await Process.run('curl.exe', [
      '--silent',
      '--show-error',
      '--proxy',
      'http://127.0.0.1:$proxyPort',
      '--connect-timeout',
      '3',
      '--max-time',
      max(5, (timeoutMs / 1000).ceil()).toString(),
      endpoint,
    ]);
    if (result.exitCode != 0) {
      errors.add(result.stderr.toString().trim());
      continue;
    }
    try {
      final body = jsonDecode(result.stdout.toString());
      final countryCode =
          (body['country_code'] ?? body['countryCode'] ?? body['country'] ?? '')
              .toString()
              .toUpperCase();
      if (countryCode.isEmpty) {
        errors.add('$endpoint 未返回国家/地区');
        continue;
      }
      return _GeoProbeResult(countryCode != 'CN');
    } catch (_) {
      errors.add('$endpoint 返回格式无效');
    }
  }
  return _GeoProbeResult(false,
      error: errors.where((e) => e.isNotEmpty).join('; '));
}

Future<int> _freePort() async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final port = server.port;
  await server.close();
  return port;
}

Future<void> _waitForLocalPort(int port, int timeoutMs) async {
  final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
  while (DateTime.now().millisecondsSinceEpoch < deadline) {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 250));
      await socket.close();
      return;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }
  throw Exception('health proxy did not start');
}
