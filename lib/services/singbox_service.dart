import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/models/node.dart';
import '../core/remote_dns.dart';
import '../core/singbox_config.dart';

/// Callback for sing-box process state changes.
typedef OnSingBoxState = void Function({bool connected, int? pid, int? code});
typedef OnSingBoxLog = void Function(String line);

/// A bounded snapshot of the desktop sing-box process for UI and diagnostics.
class SingBoxRuntimeSnapshot {
  SingBoxRuntimeSnapshot({
    required this.running,
    this.pid,
    this.startedAt,
    this.configPath,
    this.exitCode,
    List<String> recentLogs = const [],
  }) : recentLogs = recentLogs.length <= 120
            ? recentLogs
            : List<String>.unmodifiable(
                recentLogs.sublist(recentLogs.length - 120),
              );

  final bool running;
  final int? pid;
  final DateTime? startedAt;
  final String? configPath;
  final int? exitCode;
  final List<String> recentLogs;

  SingBoxRuntimeSnapshot copyWith({
    bool? running,
    int? pid,
    DateTime? startedAt,
    String? configPath,
    int? exitCode,
    List<String>? recentLogs,
  }) {
    return SingBoxRuntimeSnapshot(
      running: running ?? this.running,
      pid: pid ?? this.pid,
      startedAt: startedAt ?? this.startedAt,
      configPath: configPath ?? this.configPath,
      exitCode: exitCode ?? this.exitCode,
      recentLogs: recentLogs ?? this.recentLogs,
    );
  }
}

/// Manages the sing-box core process.
class SingBoxController {
  final String corePath;
  final String runtimeDir;
  final OnSingBoxState? onState;
  final OnSingBoxLog? onLog;
  final Duration startupGracePeriod;

  Process? _process;
  int _runId = 0;
  SingBoxRuntimeSnapshot _snapshot = SingBoxRuntimeSnapshot(running: false);
  String? get configPath => _configPath;
  String? _configPath;

  SingBoxController({
    required this.corePath,
    required this.runtimeDir,
    this.onState,
    this.onLog,
    this.startupGracePeriod = const Duration(milliseconds: 250),
  });

  bool get isRunning => _process != null && _process!.pid > 0;
  SingBoxRuntimeSnapshot get snapshot => _snapshot;

  Future<void> ensureReady() async {
    if (!await File(corePath).exists()) {
      throw Exception('sing-box core not found: $corePath');
    }
    final dir = Directory('${runtimeDir}/runtime');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Connect to a node by starting sing-box.
  Future<Map<String, dynamic>> connect({
    required VpnNode node,
    String mode = 'global',
    bool tunEnabled = false,
    RemoteDnsProvider remoteDnsProvider = RemoteDnsProvider.cloudflare,
  }) async {
    _runId++;
    final currentRunId = _runId;

    // Kill previous process
    await _process?.kill();
    _process = null;

    await ensureReady();

    final config = buildSingBoxConfig(
      node: node,
      mode: mode,
      tunEnabled: tunEnabled,
      remoteDnsProvider: remoteDnsProvider,
    );

    final runDir = Directory('${runtimeDir}/runtime');
    if (!await runDir.exists()) await runDir.create(recursive: true);

    _configPath = '${runDir.path}/sing-box.json';
    await File(_configPath!).writeAsString(singBoxConfigToJson(config));

    _process = await Process.start(
      corePath,
      ['run', '-c', _configPath!],
      mode: ProcessStartMode.normal,
      runInShell: Platform.isWindows,
    );

    final pid = _process!.pid;
    _snapshot = SingBoxRuntimeSnapshot(
      running: true,
      pid: pid,
      startedAt: DateTime.now(),
      configPath: _configPath,
    );

    _process!.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) {
      if (_runId != currentRunId) return;
      log(line);
    });

    _process!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) {
      if (_runId != currentRunId) return;
      log(line);
    });

    final exitCodeFuture = _process!.exitCode;
    exitCodeFuture.then((code) {
      if (_runId != currentRunId) return;
      _snapshot = _snapshot.copyWith(running: false, exitCode: code);
      onState?.call(connected: false, code: code);
      _process = null;
    });

    // Windows shell-backed commands can take a short scheduling interval to
    // deliver their exit notification. Keep a small floor so an immediately
    // exiting core cannot be reported as connected just because the caller
    // supplied an overly short grace period.
    final effectiveGrace = startupGracePeriod < const Duration(milliseconds: 250)
        ? const Duration(milliseconds: 250)
        : startupGracePeriod;
    final startupResult = await Future.any<dynamic>([
      exitCodeFuture,
      Future<void>.delayed(effectiveGrace),
    ]);
    if (startupResult is int) {
      throw Exception('sing-box exited during startup (code $startupResult)');
    }
    if (_runId != currentRunId || _process == null || !_snapshot.running) {
      final code = _snapshot.exitCode;
      throw Exception(
          'sing-box exited during startup${code == null ? '' : ' (code $code)'}');
    }
    onState?.call(connected: true, pid: pid);

    return {
      'mixedPort': defaultHttpPort,
      'httpPort': defaultHttpPort,
      'socksPort': defaultSocksPort,
      'apiPort': defaultApiPort,
      'configPath': _configPath,
    };
  }

  /// Disconnect the sing-box process.
  void disconnect() {
    if (_process != null) {
      _runId++;
      _process!.kill();
      _process = null;
    }
    _snapshot = _snapshot.copyWith(running: false);
    onState?.call(connected: false);
  }

  void log(String line) {
    final clean = line.trim();
    if (clean.isNotEmpty) {
      _snapshot = _snapshot.copyWith(
        recentLogs: [..._snapshot.recentLogs, clean],
      );
      onLog?.call(clean);
    }
  }

  void dispose() {
    disconnect();
  }
}
