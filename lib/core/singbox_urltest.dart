import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models/node.dart';
import 'node_health.dart';
import 'singbox_config.dart';

const singBoxUrlTestTarget = 'https://www.gstatic.com/generate_204';
const singBoxUrlTestTimeout = Duration(seconds: 3);

abstract interface class DesktopNodeHealthSession {
  Future<HealthCheckResult> check(VpnNode node);

  Future<void> close();
}

typedef DesktopNodeHealthSessionFactory = Future<DesktopNodeHealthSession>
    Function(List<VpnNode> nodes, String corePath, String runtimeDir);

Future<HealthCheckResult> querySingBoxProxyDelay({
  required int apiPort,
  required String outboundTag,
  Duration timeout = singBoxUrlTestTimeout,
  String target = singBoxUrlTestTarget,
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..findProxy = (_) => 'DIRECT';
  final uri = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: apiPort,
    pathSegments: ['proxies', outboundTag, 'delay'],
    queryParameters: {
      'timeout': timeout.inMilliseconds.toString(),
      'url': target,
    },
  );

  Future<HealthCheckResult> request() async {
    try {
      final httpRequest = await client.getUrl(uri);
      final response = await httpRequest.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        return HealthCheckResult(
          ok: false,
          healthStatus: 'unavailable',
          target: 'Clash URLTest',
          error: 'delay API returned HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(body);
      final rawDelay = decoded is Map ? decoded['delay'] : null;
      final delay = rawDelay is num
          ? rawDelay.round()
          : int.tryParse(rawDelay?.toString() ?? '');
      if (delay == null || delay <= 0) {
        return const HealthCheckResult(
          ok: false,
          healthStatus: 'unavailable',
          target: 'Clash URLTest',
          error: 'delay API returned no usable delay',
        );
      }
      return HealthCheckResult(
        ok: true,
        latency: delay,
        healthStatus: 'available',
        target: 'Clash URLTest',
      );
    } catch (error) {
      return HealthCheckResult(
        ok: false,
        healthStatus: 'unavailable',
        target: 'Clash URLTest',
        error: error.toString(),
      );
    }
  }

  try {
    return await request().timeout(
      timeout,
      onTimeout: () => const HealthCheckResult(
        ok: false,
        healthStatus: 'unavailable',
        target: 'Clash URLTest',
        error: '节点检查超时',
      ),
    );
  } finally {
    client.close(force: true);
  }
}

class SingBoxUrlTestSession implements DesktopNodeHealthSession {
  SingBoxUrlTestSession._({
    required Process process,
    required int apiPort,
    required Directory runDirectory,
    required Set<String> outboundTags,
  })  : _process = process,
        _apiPort = apiPort,
        _runDirectory = runDirectory,
        _outboundTags = outboundTags;

  final Process _process;
  final int _apiPort;
  final Directory _runDirectory;
  final Set<String> _outboundTags;
  bool _closed = false;

  static Future<SingBoxUrlTestSession> start({
    required List<VpnNode> nodes,
    required String corePath,
    required String runtimeDir,
  }) async {
    if (nodes.isEmpty) {
      throw ArgumentError.value(nodes, 'nodes', 'must not be empty');
    }
    final core = File(corePath);
    if (!await core.exists()) {
      throw Exception('sing-box core not found: $corePath');
    }

    final apiPort = await _reserveLoopbackPort();
    final runDirectory = Directory(
      '$runtimeDir${Platform.pathSeparator}urltest-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await runDirectory.create(recursive: true);
    final configFile = File(
      '${runDirectory.path}${Platform.pathSeparator}sing-box-urltest.json',
    );
    await configFile.writeAsString(
      singBoxConfigToJson(
        buildSingBoxUrlTestConfig(nodes: nodes, apiPort: apiPort),
      ),
    );

    final process = await Process.start(
      corePath,
      ['run', '-c', configFile.path],
      mode: ProcessStartMode.normal,
    );
    final recentLogs = <String>[];
    void collect(String text) {
      for (final line in text.split(RegExp(r'[\r\n]+'))) {
        final clean = line.trim();
        if (clean.isEmpty) continue;
        recentLogs.add(clean);
        if (recentLogs.length > 20) recentLogs.removeAt(0);
      }
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(collect);
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(collect);
    int? exitCode;
    unawaited(process.exitCode.then((code) => exitCode = code));

    try {
      await _waitForApi(
        apiPort,
        exitCode: () => exitCode,
        timeout: const Duration(seconds: 3),
      );
    } catch (error) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
      try {
        await runDirectory.delete(recursive: true);
      } catch (_) {}
      final detail = recentLogs.isEmpty ? '' : ': ${recentLogs.join(' | ')}';
      throw Exception('$error$detail');
    }

    return SingBoxUrlTestSession._(
      process: process,
      apiPort: apiPort,
      runDirectory: runDirectory,
      outboundTags: nodes.map(nodeOutboundTag).toSet(),
    );
  }

  @override
  Future<HealthCheckResult> check(VpnNode node) {
    final tag = nodeOutboundTag(node);
    if (_closed || !_outboundTags.contains(tag)) {
      return Future.value(const HealthCheckResult(
        ok: false,
        healthStatus: 'unavailable',
        target: 'Clash URLTest',
        error: 'node is not loaded in the URLTest core',
      ));
    }
    return querySingBoxProxyDelay(apiPort: _apiPort, outboundTag: tag);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _runDirectory.delete(recursive: true);
    } catch (_) {}
  }
}

Future<int> _reserveLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

Future<void> _waitForApi(
  int port, {
  required int? Function() exitCode,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final code = exitCode();
    if (code != null) {
      throw Exception('sing-box URLTest core exited with code $code');
    }
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 150),
      );
      socket.destroy();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw TimeoutException('sing-box URLTest API did not start', timeout);
}
