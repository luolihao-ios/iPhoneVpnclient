import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/models/node.dart';
import '../core/node_health.dart' as health;
import '../core/initial_node_screening.dart';
import '../core/node_latency.dart';
import '../core/node_storage.dart';
import '../core/subscription.dart';
import '../core/stats.dart';
import '../core/singbox_config.dart';
import '../core/singbox_urltest.dart';
import '../core/desktop_vpn_diagnostics.dart';
import '../core/update_checker.dart';
import '../services/singbox_service.dart';
import '../services/android_vpn_service.dart';
import '../services/ios_vpn_service.dart';
import '../services/windows_proxy_service.dart';

/// Application settings.
class AppSettings {
  final bool systemProxy;
  final bool tunEnabled;
  final String routeMode;
  final bool autoStart;
  final bool darkMode;

  const AppSettings({
    this.systemProxy = true,
    this.tunEnabled = false,
    this.routeMode = 'global',
    this.autoStart = false,
    this.darkMode = true,
  });

  AppSettings copyWith({
    bool? systemProxy,
    bool? tunEnabled,
    String? routeMode,
    bool? autoStart,
    bool? darkMode,
  }) {
    return AppSettings(
      systemProxy: systemProxy ?? this.systemProxy,
      tunEnabled: tunEnabled ?? this.tunEnabled,
      routeMode: routeMode ?? this.routeMode,
      autoStart: autoStart ?? this.autoStart,
      darkMode: darkMode ?? this.darkMode,
    );
  }
}

/// Runtime state for the VPN connection.
class RuntimeState {
  final bool connected;
  final bool checkingNodes;
  final int? latency;
  final int upSpeed;
  final int downSpeed;
  final List<String> logs;
  final String proxyWarning;

  const RuntimeState({
    this.connected = false,
    this.checkingNodes = false,
    this.latency,
    this.upSpeed = 0,
    this.downSpeed = 0,
    this.logs = const [],
    this.proxyWarning = '',
  });

  RuntimeState copyWith({
    bool? connected,
    bool? checkingNodes,
    int? latency,
    int? upSpeed,
    int? downSpeed,
    List<String>? logs,
    String? proxyWarning,
  }) {
    return RuntimeState(
      connected: connected ?? this.connected,
      checkingNodes: checkingNodes ?? this.checkingNodes,
      latency: latency ?? this.latency,
      upSpeed: upSpeed ?? this.upSpeed,
      downSpeed: downSpeed ?? this.downSpeed,
      logs: logs ?? this.logs,
      proxyWarning: proxyWarning ?? this.proxyWarning,
    );
  }
}

typedef SubscriptionLoader = Future<List<VpnNode>> Function(
  String url,
  void Function(String message) onDiagnostic,
);
typedef NodeTcpChecker = Future<health.HealthCheckResult> Function(
  VpnNode node,
);
typedef NodeFullChecker = Future<health.HealthCheckResult> Function(
  VpnNode node,
  String corePath,
  String runtimeDir,
);
typedef MobileNodeHealthChecker = Future<health.HealthCheckResult> Function(
  VpnNode node,
);
typedef ConnectionAttemptStarter = Future<void> Function(
  VpnNode node,
  AppSettings settings,
);

/// Main application state provider.
class AppProvider extends ChangeNotifier {
  AppProvider({
    WindowsProxyService? windowsProxy,
    SubscriptionLoader? subscriptionLoader,
    NodeTcpChecker? tcpChecker,
    NodeFullChecker? fullChecker,
    MobileNodeHealthChecker? mobileHealthChecker,
    DesktopNodeHealthSessionFactory? desktopHealthSessionFactory,
    ConnectionAttemptStarter? connectionAttemptStarter,
    String initialAppVersion = '--',
  })  : _windowsProxy = windowsProxy ?? WindowsProxyService(),
        _subscriptionLoader = subscriptionLoader ??
            ((url, onDiagnostic) =>
                fetchSubscription(url, onDiagnostic: onDiagnostic)),
        _tcpChecker = tcpChecker ??
            ((node) => health.checkNodeTcpAvailability(node: node)),
        _fullChecker = fullChecker ??
            ((node, corePath, runtimeDir) => health.checkNodeAvailability(
                  corePath: corePath,
                  runtimeDir: runtimeDir,
                  node: node,
                )),
        _mobileHealthChecker = mobileHealthChecker,
        _desktopHealthSessionFactory = desktopHealthSessionFactory,
        _hasInjectedFullChecker = fullChecker != null,
        _hasInjectedHealthCheckers = tcpChecker != null ||
            fullChecker != null ||
            mobileHealthChecker != null ||
            desktopHealthSessionFactory != null,
        _connectionAttemptStarter = connectionAttemptStarter,
        _appVersion = initialAppVersion;
  static const _subscriptionUrlKey = 'subscription_url';
  static const _nodesKey = 'subscription_nodes';
  static const _selectedNodeKey = 'selected_node_id';
  static const _routeModeKey = 'route_mode';
  static const _systemProxyKey = 'system_proxy';

  List<VpnNode> _nodes = [];
  String _selectedNodeId = '';
  AppSettings _settings = const AppSettings();
  RuntimeState _runtime = const RuntimeState();
  String _subscriptionUrl = '';

  SingBoxController? _controller;
  AndroidVpnService? _androidVpn;
  IosVpnService? _iosVpn;
  final WindowsProxyService _windowsProxy;
  final SubscriptionLoader _subscriptionLoader;
  final NodeTcpChecker _tcpChecker;
  final NodeFullChecker _fullChecker;
  final MobileNodeHealthChecker? _mobileHealthChecker;
  final DesktopNodeHealthSessionFactory? _desktopHealthSessionFactory;
  final bool _hasInjectedFullChecker;
  final bool _hasInjectedHealthCheckers;
  final ConnectionAttemptStarter? _connectionAttemptStarter;
  Completer<void>? _mobileConnectionCompleter;
  Timer? _statsTimer;
  int _latencyBatchId = 0;
  Completer<void>? _nodeCheckCancellation;
  int _subscriptionRevision = 0;
  bool _isSwitching = false;
  WindowsUpdateInfo? _availableUpdate;
  String _appVersion;

  /// Platform detection.
  static bool get _isAndroid =>
      !kIsWeb && Platform.operatingSystem == 'android';
  static bool get _isiOS => !kIsWeb && Platform.operatingSystem == 'ios';
  bool get _usesMobileCoreHealth =>
      _isAndroid || _isiOS || _mobileHealthChecker != null;
  bool get _usesDesktopUrlTest =>
      !_usesMobileCoreHealth &&
      !_hasInjectedFullChecker &&
      (_desktopHealthSessionFactory != null || _controller != null);

  Future<DesktopNodeHealthSession> _openDesktopHealthSession(
    List<VpnNode> nodes,
  ) {
    final corePath = _controller?.corePath ?? '';
    final runtimeDir = _controller?.runtimeDir ?? Directory.systemTemp.path;
    final factory = _desktopHealthSessionFactory;
    if (factory != null) return factory(nodes, corePath, runtimeDir);
    return SingBoxUrlTestSession.start(
      nodes: nodes,
      corePath: corePath,
      runtimeDir: runtimeDir,
    );
  }

  Future<health.HealthCheckResult> _checkMobileNode(VpnNode node) async {
    final injected = _mobileHealthChecker;
    if (injected != null) return injected(node);
    if (_isiOS) {
      if (_iosVpn == null) await _initIOS();
      return _iosVpn!.checkNodeHealth(nodeOutboundTag(node));
    }
    if (_isAndroid) {
      if (_androidVpn == null) await _initAndroid();
      return _androidVpn!.checkNodeHealth(nodeOutboundTag(node));
    }
    return const health.HealthCheckResult(
      ok: false,
      healthStatus: 'unavailable',
      target: 'HTTP 204',
      error: 'Native sing-box health checker is unavailable',
    );
  }

  /// Auto-detect sing-box binary path for desktop platforms.
  static String _detectCorePath() {
    if (Platform.isWindows) {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$executableDir/sing-box.exe',
        '$executableDir/data/sing-box.exe',
        '$executableDir/data/flutter_assets/assets/binaries/sing-box-windows-amd64.exe',
        '../desktop-vpn-client/resources/bin/sing-box.exe',
        './sing-box.exe',
        'C:/tools/sing-box/sing-box.exe',
      ];
      for (final p in candidates) {
        final f = File(p);
        if (f.existsSync()) return f.absolute.path;
      }
    } else if (Platform.isLinux) {
      for (final p in ['/usr/local/bin/sing-box', '/usr/bin/sing-box']) {
        final f = File(p);
        if (f.existsSync()) return f.absolute.path;
      }
    } else if (Platform.isMacOS) {
      for (final p in [
        '/usr/local/bin/sing-box',
        '/opt/homebrew/bin/sing-box'
      ]) {
        final f = File(p);
        if (f.existsSync()) return f.absolute.path;
      }
    }
    return '';
  }

  // Getters
  List<VpnNode> get nodes => sortNodesByLatency(_nodes);
  String get selectedNodeId => _selectedNodeId;
  AppSettings get settings => _settings;
  RuntimeState get runtime => _runtime;
  String get subscriptionUrl => _subscriptionUrl;
  bool get isSwitching => _isSwitching;
  WindowsUpdateInfo? get availableUpdate => _availableUpdate;
  String get appVersion => _appVersion;

  VpnNode? get selectedNode {
    if (nodes.isEmpty) return null;
    return nodes.firstWhere(
      (n) => n.id == _selectedNodeId,
      orElse: () => nodes.first,
    );
  }

  /// Initialize the controller (platform-appropriate).
  Future<void> initialize(String corePath) async {
    await _loadAppVersion();
    if (_isiOS) {
      await _initIOS();
    } else if (_isAndroid) {
      await _initAndroid();
    } else {
      await _initDesktop(corePath);
    }

    // Restore saved subscription URL
    await _restoreSubscription();
    if (_nodes.isNotEmpty && (!_usesMobileCoreHealth || _runtime.connected)) {
      unawaited(startInitialNodeScreening().catchError((error) {
        log('Startup node screening failed: $error');
      }));
    }
    unawaited(checkForUpdates());
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        final build = int.tryParse(info.buildNumber.trim());
        _appVersion = build == null
            ? version
            : '$version.${build.toString().padLeft(3, '0')}';
      }
    } catch (_) {
      // Keep the visible placeholder for tests and unsupported platforms.
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    final update = await fetchWindowsUpdate(currentVersion: _appVersion);
    if (update == null) return;
    _availableUpdate = update;
    notifyListeners();
  }

  Future<void> openUpdate() async {
    final update = _availableUpdate;
    if (update == null) return;
    await openWindowsUpdate(update);
  }

  void dismissUpdate() {
    if (_availableUpdate == null) return;
    _availableUpdate = null;
    notifyListeners();
  }

  Future<void> _restoreSubscription() async {
    var restored = false;
    final revisionAtStart = _subscriptionRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRouteMode = prefs.getString(_routeModeKey);
      if (savedRouteMode == 'global' || savedRouteMode == 'rule') {
        _settings = _settings.copyWith(routeMode: savedRouteMode);
        restored = true;
      }
      if (prefs.containsKey(_systemProxyKey)) {
        _settings = _settings.copyWith(
            systemProxy: prefs.getBool(_systemProxyKey) ?? true);
        restored = true;
      }
      final savedUrl = prefs.getString(_subscriptionUrlKey) ?? '';
      if (savedUrl.isNotEmpty && revisionAtStart == _subscriptionRevision) {
        _subscriptionUrl = savedUrl;
        log('Restored subscription URL from cache');
        restored = true;
      }
      final savedNodes = prefs.getString(_nodesKey);
      if (savedNodes != null && revisionAtStart == _subscriptionRevision) {
        final nodes = decodeNodes(savedNodes);
        if (nodes.isNotEmpty) {
          _nodes = nodes;
          _selectedNodeId = prefs.getString(_selectedNodeKey) ?? '';
          if (!_nodes.any((node) => node.id == _selectedNodeId)) {
            _selectedNodeId = _nodes.first.id;
          }
          log('Restored ${_nodes.length} subscription nodes from cache');
          restored = true;
        }
      }
    } catch (_) {}
    if (restored) notifyListeners();
  }

  Future<void> _persistNodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nodesKey, encodeNodes(_nodes));
      await prefs.setString(_selectedNodeKey, _selectedNodeId);
    } catch (_) {}
  }

  Future<void> _initAndroid() async {
    _androidVpn = AndroidVpnService();

    _androidVpn!.onStatus = (status, message) {
      switch (status) {
        case 'connected':
          final androidConnectedPending = _mobileConnectionCompleter;
          if (androidConnectedPending != null &&
              !androidConnectedPending.isCompleted) {
            androidConnectedPending.complete();
          } else {
            _runtime = _runtime.copyWith(connected: true, proxyWarning: '');
          }
          notifyListeners();
          break;
        case 'disconnected':
          final androidDisconnectedPending = _mobileConnectionCompleter;
          if (androidDisconnectedPending != null &&
              !androidDisconnectedPending.isCompleted) {
            androidDisconnectedPending.completeError(
              Exception(message.isEmpty ? 'VPN disconnected' : message),
            );
          }
          _runtime = _runtime.copyWith(connected: false, proxyWarning: message);
          _statsTimer?.cancel();
          notifyListeners();
          break;
        case 'error':
          log('VPN Error: $message');
          final androidErrorPending = _mobileConnectionCompleter;
          if (androidErrorPending != null && !androidErrorPending.isCompleted) {
            androidErrorPending.completeError(Exception(message));
          }
          _runtime = _runtime.copyWith(connected: false);
          notifyListeners();
          break;
        case 'permission_granted':
          log('VPN permission granted');
          notifyListeners();
          break;
        case 'permission_denied':
          log('VPN permission denied');
          notifyListeners();
          break;
        case 'ready':
        case 'connecting':
        case 'disconnecting':
          log('VPN state: $status${message.isEmpty ? '' : ' ($message)'}');
          break;
      }
    };

    _androidVpn!.onLog = (line) {
      log(line);
    };
    await _androidVpn!.restoreState();
  }

  Future<void> _initIOS() async {
    _iosVpn = IosVpnService();

    _iosVpn!.onStatus = (status, message) {
      switch (status) {
        case 'connected':
          final iosConnectedPending = _mobileConnectionCompleter;
          if (iosConnectedPending != null && !iosConnectedPending.isCompleted) {
            iosConnectedPending.complete();
          } else {
            _runtime = _runtime.copyWith(connected: true, proxyWarning: '');
          }
          notifyListeners();
          break;
        case 'disconnected':
          final iosDisconnectedPending = _mobileConnectionCompleter;
          if (iosDisconnectedPending != null &&
              !iosDisconnectedPending.isCompleted) {
            iosDisconnectedPending.completeError(
              Exception(message.isEmpty ? 'VPN disconnected' : message),
            );
          }
          _runtime = _runtime.copyWith(connected: false, proxyWarning: message);
          _statsTimer?.cancel();
          notifyListeners();
          break;
        case 'error':
          log('VPN Error: $message');
          final iosErrorPending = _mobileConnectionCompleter;
          if (iosErrorPending != null && !iosErrorPending.isCompleted) {
            iosErrorPending.completeError(Exception(message));
          }
          _runtime = _runtime.copyWith(connected: false);
          notifyListeners();
          break;
      }
    };

    _iosVpn!.onLog = (line) {
      log(line);
    };
    await _iosVpn!.restoreState();
  }

  Future<void> _initDesktop(String suppliedPath) async {
    // A previous process may have been terminated or the computer may have
    // rebooted while Forge VPN owned the system proxy. Recover it before any
    // new connection is started.
    await _windowsProxy.recoverStaleSettings();
    final corePath = suppliedPath.isNotEmpty ? suppliedPath : _detectCorePath();
    if (corePath.isEmpty) {
      log('Warning: sing-box binary not found. Connection will fail.');
    } else {
      log('Core path: $corePath');
    }
    final appDir = await getApplicationSupportDirectory();
    final runtimeDir = appDir.path;

    _controller = SingBoxController(
      corePath: corePath,
      runtimeDir: runtimeDir,
      onState: ({bool? connected, int? pid, int? code}) {
        final isConnected = connected == true;
        _runtime = _runtime.copyWith(connected: isConnected);
        if (isConnected) {
          _startStats();
        } else {
          unawaited(_restoreWindowsProxy());
          _statsTimer?.cancel();
          _runtime =
              _runtime.copyWith(upSpeed: 0, downSpeed: 0, proxyWarning: '');
          if (code != null) log('sing-box exited with code $code');
        }
        notifyListeners();
      },
      onLog: (line) {
        log(line);
      },
    );
  }

  /// Import nodes from a subscription URL.
  Future<void> importSubscription(String url) async {
    final importRevision = ++_subscriptionRevision;
    stopNodeChecks();
    final resolvedUrl = resolveSubscriptionInput(url);
    if (resolvedUrl == null) {
      throw Exception(
          'Unsupported subscription link. Paste an HTTPS or Stash install link.');
    }
    final fetchedNodes = await _subscriptionLoader(
      resolvedUrl,
      log,
    );
    if (importRevision != _subscriptionRevision) return;
    _latencyBatchId++;
    _nodes = sortNodesByLatency(fetchedNodes);
    _subscriptionUrl = resolvedUrl;

    // Persist subscription URL
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subscriptionUrlKey, resolvedUrl);
    } catch (_) {}

    if (!_nodes.any((n) => n.id == _selectedNodeId)) {
      _selectedNodeId = _nodes.isNotEmpty ? _nodes.first.id : '';
    }
    await _persistNodes();
    notifyListeners();

    _scheduleInitialNodeScreeningAfterImport();
  }

  /// Import nodes from raw subscription text.
  Future<void> importSubscriptionText(String rawText) async {
    ++_subscriptionRevision;
    stopNodeChecks();
    final parsedNodes = parseSubscription(rawText);
    _latencyBatchId++;
    _nodes = sortNodesByLatency(parsedNodes);

    if (!_nodes.any((n) => n.id == _selectedNodeId)) {
      _selectedNodeId = _nodes.isNotEmpty ? _nodes.first.id : '';
    }
    await _persistNodes();
    notifyListeners();
    _scheduleInitialNodeScreeningAfterImport();
  }

  void _scheduleInitialNodeScreeningAfterImport() {
    if (_usesMobileCoreHealth && !_runtime.connected) {
      log('Node health check will start after the mobile VPN core is connected');
      return;
    }
    unawaited(startInitialNodeScreening());
  }

  /// Select a node.
  void selectNode(String nodeId) {
    _selectedNodeId = nodeId;
    final node = selectedNode;
    _runtime = _runtime.copyWith(latency: node?.latencyMs);
    if (_runtime.connected && node != null && _usesMobileCoreHealth) {
      unawaited(_selectMobileOutbound(node));
    }
    unawaited(_persistNodes());
    notifyListeners();
  }

  Future<void> _selectMobileOutbound(VpnNode node) async {
    final tag = nodeOutboundTag(node);
    final selected = _isiOS
        ? await _iosVpn?.selectNode(tag)
        : _isAndroid
            ? await _androidVpn?.selectNode(tag)
            : true;
    if (selected != true) {
      log('Failed to select node in mobile core: ${node.name}');
    }
  }

  /// Ping a single node.
  Future<health.HealthCheckResult?> pingNode(String nodeId) async {
    final node = nodes.firstWhere((n) => n.id == nodeId);
    if (!_canCheckNodes) return null;

    _latencyBatchId++;
    _nodes = _nodes
        .map((n) => n.id == nodeId
            ? n.copyWith(
                healthStatus: HealthStatus.checking,
                clearLatencyMs: true,
                clearHealthDetails: true,
              )
            : n)
        .toList();
    notifyListeners();

    if (_usesMobileCoreHealth) {
      final result = await _checkMobileNode(node);
      _nodes = updateNodeLatency(_nodes, nodeId, result);
      _runtime = _runtime.copyWith(latency: selectedNode?.latencyMs);
      notifyListeners();
      return result;
    }

    late health.HealthCheckResult result;
    if (_usesDesktopUrlTest) {
      DesktopNodeHealthSession? session;
      try {
        session = await _openDesktopHealthSession([node]);
        result = await session.check(node);
      } catch (error) {
        result = health.HealthCheckResult(
          ok: false,
          healthStatus: 'unavailable',
          target: 'Clash URLTest',
          error: error.toString(),
        );
        log('Node URLTest failed to start: $error');
      } finally {
        await session?.close();
      }
    } else {
      result = await _fullChecker(
        node,
        _controller?.corePath ?? '',
        '${_controller?.runtimeDir ?? '/'}/health',
      );
    }

    _nodes = updateNodeLatency(_nodes, nodeId, result);
    _runtime = _runtime.copyWith(latency: selectedNode?.latencyMs);
    notifyListeners();
    return result;
  }

  bool get _canCheckNodes =>
      _isAndroid || _isiOS || _controller != null || _hasInjectedHealthCheckers;

  void stopNodeChecks() {
    _latencyBatchId++;
    final cancellation = _nodeCheckCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _nodeCheckCancellation = null;
    _nodes = _nodes
        .map((node) => node.healthStatus == HealthStatus.checking
            ? resetNodeHealth(node)
            : node)
        .toList();
    _runtime = _runtime.copyWith(checkingNodes: false);
    unawaited(_persistNodes());
    notifyListeners();
  }

  Future<void> startInitialNodeScreening() async {
    if (_nodes.isEmpty || !_canCheckNodes) return;

    final previousCancellation = _nodeCheckCancellation;
    if (previousCancellation != null && !previousCancellation.isCompleted) {
      previousCancellation.complete();
    }
    final cancellation = Completer<void>();
    _nodeCheckCancellation = cancellation;
    final batchId = ++_latencyBatchId;
    _nodes = _nodes.map(resetNodeHealth).toList();
    final nodesToCheck = List<VpnNode>.from(_nodes);
    _runtime = _runtime.copyWith(
      checkingNodes: true,
      latency: selectedNode?.latencyMs,
    );
    notifyListeners();

    bool isCurrentBatch() => batchId == _latencyBatchId;

    void updateNode(String nodeId, VpnNode Function(VpnNode node) update,
        {bool notify = true}) {
      if (!isCurrentBatch()) return;
      _nodes = _nodes
          .map((node) => node.id == nodeId ? update(node) : node)
          .toList();
      if (notify) notifyListeners();
    }

    final corePath = _controller?.corePath ?? '';
    final healthDir = '${_controller?.runtimeDir ?? '/'}/health';

    DesktopNodeHealthSession? desktopSession;
    try {
      if (_usesDesktopUrlTest) {
        desktopSession = await _openDesktopHealthSession(nodesToCheck);
      }
      final summary = await runInitialNodeScreening(
        nodes: nodesToCheck,
        validationTarget: desktopSession == null ? 'HTTP 204' : 'Clash URLTest',
        tcpProbe: (node) async {
          // A mobile Socket.connect would be routed through the currently
          // selected VPN node and creates a false positive. Let every
          // candidate reach the core URLTest stage instead.
          if (_usesMobileCoreHealth || desktopSession != null) return 1;
          final result = await _awaitNodeCheck(
            _tcpChecker(node),
            cancellation: cancellation.future,
            timeout: const Duration(milliseconds: 1200),
            onTimeout: health.HealthCheckResult(
              ok: false,
              healthStatus: 'unavailable',
              target: 'Node',
              error: 'TCP connection timed out',
            ),
          );
          return result.ok ? result.latency : null;
        },
        validate: (node) {
          final check = _usesMobileCoreHealth
              ? _checkMobileNode(node)
              : desktopSession != null
                  ? desktopSession.check(node)
                  : _fullChecker(node, corePath, healthDir);
          return _awaitNodeCheck(
            check,
            cancellation: cancellation.future,
            timeout: const Duration(seconds: 3),
            onTimeout: health.HealthCheckResult(
              ok: false,
              healthStatus: 'unavailable',
              target: desktopSession == null ? 'HTTP 204' : 'Clash URLTest',
              error: '节点检查超时',
            ),
          );
        },
        onNodeChecking: (node) {
          updateNode(
            node.id,
            (current) => current.copyWith(
              healthStatus: HealthStatus.checking,
              clearLatencyMs: true,
              clearHealthDetails: true,
            ),
          );
        },
        onTcpReachable: (node, _) {
          updateNode(node.id, resetNodeHealth, notify: false);
        },
        onNodeResult: (node, result) {
          if (!result.ok && result.target != 'Node') {
            final error =
                result.error?.replaceAll(RegExp(r'[\r\n]+'), ' ') ?? 'unknown';
            log(
              'node health failed: node=${node.name} target=${result.target} '
              'error=$error',
            );
          }
          updateNode(
            node.id,
            (current) =>
                updateNodeLatency([current], current.id, result).single,
            notify: result.target != 'Node',
          );
        },
        isCancelled: () => !isCurrentBatch(),
      );
      if (isCurrentBatch()) {
        log(
          'Initial node screening finished: tcp=${summary.tcpCheckedCount} '
          'validated=${summary.validatedCount} available=${summary.availableCount} '
          'exhausted=${summary.exhaustedCandidates}',
        );
      }
    } catch (error) {
      if (isCurrentBatch()) log('Initial node screening failed: $error');
    } finally {
      await desktopSession?.close();
      if (isCurrentBatch()) {
        _nodes = _nodes
            .map((node) => node.healthStatus == HealthStatus.checking
                ? resetNodeHealth(node)
                : node)
            .toList();
        _runtime = _runtime.copyWith(
          checkingNodes: false,
          latency: selectedNode?.latencyMs,
        );
        await _persistNodes();
        notifyListeners();
      }
      if (identical(_nodeCheckCancellation, cancellation)) {
        _nodeCheckCancellation = null;
      }
    }
  }

  /// Check all nodes' health.
  Future<void> checkAllNodes() async {
    if (nodes.isEmpty) return;

    final previousCancellation = _nodeCheckCancellation;
    if (previousCancellation != null && !previousCancellation.isCompleted) {
      previousCancellation.complete();
    }
    final cancellation = Completer<void>();
    _nodeCheckCancellation = cancellation;
    final batchId = ++_latencyBatchId;
    _nodes = prepareNodesForLatencyTest(_nodes);
    // Keep a stable order for this batch. The public `nodes` getter sorts by
    // current health/latency, so reading it by index while results arrive can
    // reorder the list and skip nodes permanently.
    final nodesToCheck = List<VpnNode>.from(_nodes);
    _runtime = _runtime.copyWith(
        checkingNodes: true, latency: selectedNode?.latencyMs);
    notifyListeners();

    const concurrency = 3;
    int cursor = 0;

    final corePath = _controller?.corePath ?? '';
    final healthDir = '${_controller?.runtimeDir ?? '/'}/health';

    void resetRemainingChecks(String reason) {
      if (batchId != _latencyBatchId) return;
      _latencyBatchId++;
      _nodes = _nodes
          .map((node) => node.healthStatus == HealthStatus.checking
              ? resetNodeHealth(node)
              : node)
          .toList();
      _runtime = _runtime.copyWith(checkingNodes: false);
      log(reason);
      notifyListeners();
    }

    DesktopNodeHealthSession? desktopSession;
    try {
      if (_usesDesktopUrlTest) {
        desktopSession = await _openDesktopHealthSession(nodesToCheck);
      }
    } catch (error) {
      resetRemainingChecks('Node URLTest core failed to start: $error');
      return;
    }

    final workers =
        List.generate(min(concurrency, nodesToCheck.length), (_) async {
      while (cursor < nodesToCheck.length && batchId == _latencyBatchId) {
        final node = nodesToCheck[cursor];
        cursor++;

        late health.HealthCheckResult result;
        try {
          result = await _awaitNodeCheck(
            _usesMobileCoreHealth
                ? _checkMobileNode(node)
                : desktopSession != null
                    ? desktopSession.check(node)
                    : _fullChecker(node, corePath, healthDir),
            cancellation: cancellation.future,
            timeout: const Duration(seconds: 3),
            onTimeout: health.HealthCheckResult(
              ok: false,
              healthStatus: 'unavailable',
              target: desktopSession == null ? 'HTTP 204' : 'Clash URLTest',
              error: '节点检查超时',
            ),
          );
        } catch (error) {
          result = health.HealthCheckResult(
            ok: false,
            healthStatus: 'unavailable',
            target: (_isAndroid || _isiOS) ? 'Node' : 'HTTP 204',
            error: error.toString(),
          );
          log('Node health check failed for ${node.name}: $error');
        }
        if (batchId != _latencyBatchId) return;
        _nodes = updateNodeLatency(_nodes, node.id, result);
        _runtime = _runtime.copyWith(latency: selectedNode?.latencyMs);
        notifyListeners();
      }
    });

    final batchTimeout = Duration(
      seconds: max(
          30, ((nodesToCheck.length + concurrency - 1) ~/ concurrency) * 3 + 5),
    );
    try {
      await Future.wait(workers).timeout(batchTimeout);
    } on TimeoutException {
      if (batchId == _latencyBatchId) {
        resetRemainingChecks(
            'Node health check batch timed out after ${batchTimeout.inSeconds} seconds');
      }
      return;
    } catch (error) {
      log('Node health check batch failed: $error');
      resetRemainingChecks('Node health check batch stopped unexpectedly');
    } finally {
      await desktopSession?.close();
    }
    if (batchId == _latencyBatchId) {
      _runtime = _runtime.copyWith(checkingNodes: false);
      notifyListeners();
    }
    if (identical(_nodeCheckCancellation, cancellation)) {
      _nodeCheckCancellation = null;
    }
  }

  Future<health.HealthCheckResult> _awaitNodeCheck(
    Future<health.HealthCheckResult> check, {
    required Future<void> cancellation,
    required Duration timeout,
    required health.HealthCheckResult onTimeout,
  }) {
    final result = Completer<health.HealthCheckResult>();
    Timer? timer;

    void complete(health.HealthCheckResult value) {
      if (result.isCompleted) return;
      timer?.cancel();
      result.complete(value);
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (result.isCompleted) return;
      timer?.cancel();
      result.completeError(error, stackTrace);
    }

    timer = Timer(timeout, () => complete(onTimeout));
    unawaited(cancellation.then((_) => complete(onTimeout)));
    unawaited(check.then(complete, onError: completeError));
    return result.future;
  }

  /// Connect to the selected node.
  Future<void> connect({AppSettings? settingsPatch}) async {
    final node = selectedNode;
    if (node == null) throw Exception('Please import and select a node first.');

    final mergedSettings = settingsPatch != null
        ? _settings.copyWith(
            systemProxy: settingsPatch.systemProxy,
            tunEnabled: settingsPatch.tunEnabled,
            routeMode: settingsPatch.routeMode,
          )
        : _settings;

    _settings = mergedSettings;
    _runtime = _runtime.copyWith(connected: false, proxyWarning: '');
    _isSwitching = true;
    notifyListeners();

    try {
      await _startConnectionAttempt(node, mergedSettings);
      _runtime = _runtime.copyWith(connected: true, proxyWarning: '');
      if (_connectionAttemptStarter == null) _startStats();
      notifyListeners();
      if (_usesMobileCoreHealth) {
        unawaited(startInitialNodeScreening());
      }
    } catch (_) {
      _runtime = _runtime.copyWith(connected: false);
      notifyListeners();
      rethrow;
    } finally {
      _isSwitching = false;
      notifyListeners();
    }
  }

  Future<void> _startConnectionAttempt(
    VpnNode node,
    AppSettings settings,
  ) async {
    final injected = _connectionAttemptStarter;
    if (injected != null) {
      await injected(node, settings);
      return;
    }
    if (_isiOS) {
      await _connectIOS(node, settings);
    } else if (_isAndroid) {
      await _connectAndroid(node, settings);
    } else {
      await _connectDesktop(node, settings);
    }
  }

  Future<void> _connectAndroid(
    VpnNode node,
    AppSettings settings,
  ) async {
    if (_androidVpn == null) {
      await _initAndroid();
    }

    // Build the sing-box config JSON
    final config = buildSingBoxConfig(
      node: node,
      nodes: _nodes,
      mode: settings.routeMode,
      tunEnabled: true, // Android always uses TUN
    );
    final configJson = singBoxConfigToJson(config);

    // Request permission if needed
    if (!_androidVpn!.hasPermission) {
      _isSwitching = true;
      notifyListeners();

      log('Requesting VPN permission...');
      final granted = await _androidVpn!.requestPermission();
      if (!granted) {
        _isSwitching = false;
        notifyListeners();
        throw Exception('VPN permission was denied');
      }
      log('VPN permission granted');
    }

    log('Starting VPN (Android TUN)...');
    final connected = Completer<void>();
    _mobileConnectionCompleter = connected;
    final ok = await _androidVpn!.connect(configJson);
    if (!ok) {
      _mobileConnectionCompleter = null;
      throw Exception('Failed to start VPN service');
    }
    try {
      await connected.future.timeout(const Duration(seconds: 15));
    } finally {
      if (identical(_mobileConnectionCompleter, connected)) {
        _mobileConnectionCompleter = null;
      }
    }
  }

  Future<void> _connectIOS(
    VpnNode node,
    AppSettings settings,
  ) async {
    if (_iosVpn == null) {
      await _initIOS();
    }

    // Build the sing-box config JSON (same format as Android)
    final config = buildSingBoxConfig(
      node: node,
      nodes: _nodes,
      mode: settings.routeMode,
      tunEnabled: true, // iOS always uses TUN
      logLevel: 'debug',
    );
    final configJson = singBoxConfigToJson(config);

    log('Starting VPN (iOS TUN)...');
    log('iOS route diagnostics: mode=${settings.routeMode}, logLevel=debug');
    log('Config: ${configJson.length} bytes');
    log('Node: ${node.name} (${node.type.label})');
    if (node.type == NodeType.anytls) {
      log('AnyTLS node summary: server=${node.server}, port=${node.port}, '
          'serverName=${node.serverName}, insecure=${node.insecure}, '
          'passwordLength=${node.password?.length ?? 0}');
    }

    final connected = Completer<void>();
    _mobileConnectionCompleter = connected;
    final ok = await _iosVpn!.connect(configJson);
    if (!ok) {
      _mobileConnectionCompleter = null;
      // Error already logged via onLog callback
      throw Exception('Failed to start VPN service');
    }
    try {
      await connected.future.timeout(const Duration(seconds: 15));
    } finally {
      if (identical(_mobileConnectionCompleter, connected)) {
        _mobileConnectionCompleter = null;
      }
    }
  }

  Future<void> _connectDesktop(
    VpnNode node,
    AppSettings settings,
  ) async {
    if (_controller == null)
      throw Exception('sing-box controller not initialized.');

    // Stop any existing sing-box processes
    await _stopExistingSingBoxProcesses();

    log('Starting sing-box: route=${settings.routeMode}, tun=${settings.tunEnabled ? "on" : "off"}');

    await _controller!.connect(
      node: node,
      mode: settings.routeMode,
      tunEnabled: settings.tunEnabled,
    );
    if (settings.systemProxy) {
      await _enableWindowsProxy();
    } else {
      await _restoreWindowsProxy();
    }
  }

  Future<void> _stopConnectionAttempt() async {
    final pending = _mobileConnectionCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(Exception('VPN connection cancelled'));
    }
    _mobileConnectionCompleter = null;
    if (_isiOS) {
      await _iosVpn?.disconnect();
    } else if (_isAndroid) {
      await _androidVpn?.disconnect();
    } else {
      _controller?.disconnect();
      await _stopExistingSingBoxProcesses();
      await _restoreWindowsProxy();
    }
  }

  Future<void> _enableWindowsProxy() async {
    try {
      await _windowsProxy.enable(proxyServer: '127.0.0.1:2080');
      _runtime = _runtime.copyWith(proxyWarning: '');
      notifyListeners();
    } catch (error) {
      log('Windows system proxy unavailable: $error');
      _runtime = _runtime.copyWith(proxyWarning: '系统代理设置失败');
      notifyListeners();
    }
  }

  Future<void> _restoreWindowsProxy() async {
    if (!_windowsProxy.ownsCurrentSettings) return;
    try {
      await _windowsProxy.restore();
    } catch (error) {
      log('Windows system proxy restore failed: $error');
    }
  }

  /// Return VPN diagnostics for the current platform.
  Future<Map<String, dynamic>> diagnoseVpn() async {
    if (_isAndroid) return AndroidVpnService().diagnose();
    if (_isiOS) return IosVpnService().diagnose();
    if (_controller == null) {
      return {'platform': 'windows', 'error': 'controller unavailable'};
    }
    return collectDesktopVpnDiagnostics(
      corePath: _controller!.corePath,
      snapshot: _controller!.snapshot,
    );
  }

  /// Disconnect from current node.
  Future<void> disconnect() async {
    _statsTimer?.cancel();
    // Invalidate any in-flight node checks so late results cannot repopulate
    // the dashboard after the VPN has been stopped.
    _latencyBatchId++;

    await _stopConnectionAttempt();

    _runtime = _runtime.copyWith(
        connected: false, upSpeed: 0, downSpeed: 0, proxyWarning: '');
    notifyListeners();
  }

  /// Save settings.
  Future<void> saveSettings(AppSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routeModeKey, newSettings.routeMode);
      await prefs.setBool(_systemProxyKey, newSettings.systemProxy);
    } catch (_) {}
  }

  void log(String line) {
    final clean = line.trim();
    if (clean.isEmpty) return;
    final logs = [..._runtime.logs, clean];
    if (logs.length > 120) logs.removeRange(0, logs.length - 120);
    _runtime = _runtime.copyWith(logs: logs);
    notifyListeners();
  }

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_runtime.connected) return;
      final traffic = await readTrafficOnce();
      _runtime = _runtime.copyWith(
        upSpeed: traffic.up,
        downSpeed: traffic.down,
      );
      notifyListeners();
    });
  }

  Future<void> _stopExistingSingBoxProcesses() async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('taskkill', [
        '/f',
        '/im',
        'sing-box.exe',
      ]);
      if (result.exitCode == 0) log('Cleaned up existing sing-box processes');
    } catch (_) {}
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _controller?.dispose();
    if (Platform.isWindows) {
      _windowsProxy.restoreSync();
    } else {
      unawaited(_restoreWindowsProxy());
    }
    _androidVpn?.disconnect();
    _iosVpn?.disconnect();
    super.dispose();
  }
}
