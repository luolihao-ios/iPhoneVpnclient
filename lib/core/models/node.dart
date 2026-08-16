/// VPN node types supported by Forge VPN.
enum NodeType {
  shadowsocks,
  vmess,
  vless,
  trojan,
  anytls,
  hysteria2,
  wireguard;

  String get label {
    switch (this) {
      case NodeType.shadowsocks:
        return 'Shadowsocks';
      case NodeType.vmess:
        return 'VMess';
      case NodeType.vless:
        return 'VLESS';
      case NodeType.trojan:
        return 'Trojan';
      case NodeType.anytls:
        return 'AnyTLS';
      case NodeType.hysteria2:
        return 'Hysteria2';
      case NodeType.wireguard:
        return 'WireGuard';
    }
  }
}

/// Health check status for a node.
enum HealthStatus {
  unknown,
  checking,
  available,
  unavailable;

  String get label {
    switch (this) {
      case HealthStatus.unknown:
        return 'Unknown';
      case HealthStatus.checking:
        return 'Checking';
      case HealthStatus.available:
        return 'Yes';
      case HealthStatus.unavailable:
        return 'No';
    }
  }
}

/// Represents a parsed VPN proxy node.
class VpnNode {
  final String id;
  final NodeType type;
  final String name;
  final String server;
  final int port;

  // Shadowsocks
  final String? method;
  final String? password;
  final String? plugin;

  // VMess
  final String? uuid;
  final String? security;
  final int alterId;
  final String? transport;
  final String? host;
  final String? path;
  final bool tls;
  final String? serverName;
  final bool insecure;

  // VLESS
  final String? flow;

  // AnyTLS
  final String? idleSessionCheckInterval;
  final String? idleSessionTimeout;
  final int minIdleSession;

  // Hysteria2
  final String? obfs;
  final List<String>? alpn;
  final int? upMbps;
  final int? downMbps;

  // WireGuard
  final String? privateKey;
  final String? peerPublicKey;
  final String? preSharedKey;
  final String? localAddress;
  final List<int>? reserved;

  // Health
  final HealthStatus healthStatus;
  final int? latencyMs;
  final String? healthError;
  final String? healthTarget;
  final int? latencyCheckedAt;

  const VpnNode({
    required this.id,
    required this.type,
    required this.name,
    required this.server,
    required this.port,
    this.method,
    this.password,
    this.plugin,
    this.uuid,
    this.security,
    this.alterId = 0,
    this.transport,
    this.host,
    this.path,
    this.tls = false,
    this.serverName,
    this.insecure = false,
    this.flow,
    this.idleSessionCheckInterval,
    this.idleSessionTimeout,
    this.minIdleSession = 0,
    this.obfs,
    this.alpn,
    this.upMbps,
    this.downMbps,
    this.privateKey,
    this.peerPublicKey,
    this.preSharedKey,
    this.localAddress,
    this.reserved,
    this.healthStatus = HealthStatus.unknown,
    this.latencyMs,
    this.healthError,
    this.healthTarget,
    this.latencyCheckedAt,
  });

  VpnNode copyWith({
    String? id,
    NodeType? type,
    String? name,
    String? server,
    int? port,
    String? method,
    String? password,
    String? plugin,
    String? uuid,
    String? security,
    int? alterId,
    String? transport,
    String? host,
    String? path,
    bool? tls,
    String? serverName,
    bool? insecure,
    String? flow,
    String? idleSessionCheckInterval,
    String? idleSessionTimeout,
    int? minIdleSession,
    String? obfs,
    List<String>? alpn,
    int? upMbps,
    int? downMbps,
    String? privateKey,
    String? peerPublicKey,
    String? preSharedKey,
    String? localAddress,
    List<int>? reserved,
    HealthStatus? healthStatus,
    int? latencyMs,
    String? healthError,
    String? healthTarget,
    int? latencyCheckedAt,
    bool clearLatencyMs = false,
    bool clearHealthDetails = false,
  }) {
    return VpnNode(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      method: method ?? this.method,
      password: password ?? this.password,
      plugin: plugin ?? this.plugin,
      uuid: uuid ?? this.uuid,
      security: security ?? this.security,
      alterId: alterId ?? this.alterId,
      transport: transport ?? this.transport,
      host: host ?? this.host,
      path: path ?? this.path,
      tls: tls ?? this.tls,
      serverName: serverName ?? this.serverName,
      insecure: insecure ?? this.insecure,
      flow: flow ?? this.flow,
      idleSessionCheckInterval:
          idleSessionCheckInterval ?? this.idleSessionCheckInterval,
      idleSessionTimeout: idleSessionTimeout ?? this.idleSessionTimeout,
      minIdleSession: minIdleSession ?? this.minIdleSession,
      obfs: obfs ?? this.obfs,
      alpn: alpn ?? this.alpn,
      upMbps: upMbps ?? this.upMbps,
      downMbps: downMbps ?? this.downMbps,
      privateKey: privateKey ?? this.privateKey,
      peerPublicKey: peerPublicKey ?? this.peerPublicKey,
      preSharedKey: preSharedKey ?? this.preSharedKey,
      localAddress: localAddress ?? this.localAddress,
      reserved: reserved ?? this.reserved,
      healthStatus: healthStatus ?? this.healthStatus,
      latencyMs: clearLatencyMs ? null : latencyMs ?? this.latencyMs,
      healthError:
          clearHealthDetails ? null : healthError ?? this.healthError,
      healthTarget:
          clearHealthDetails ? null : healthTarget ?? this.healthTarget,
      latencyCheckedAt: clearHealthDetails
          ? null
          : latencyCheckedAt ?? this.latencyCheckedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'server': server,
        'port': port,
        if (method != null) 'method': method,
        if (password != null) 'password': password,
        if (plugin != null) 'plugin': plugin,
        if (uuid != null) 'uuid': uuid,
        if (security != null) 'security': security,
        'alterId': alterId,
        if (transport != null) 'transport': transport,
        if (host != null) 'host': host,
        if (path != null) 'path': path,
        'tls': tls,
        if (serverName != null) 'serverName': serverName,
        'insecure': insecure,
        if (flow != null) 'flow': flow,
        if (idleSessionCheckInterval != null)
          'idle_session_check_interval': idleSessionCheckInterval,
        if (idleSessionTimeout != null)
          'idle_session_timeout': idleSessionTimeout,
        if (minIdleSession > 0) 'min_idle_session': minIdleSession,
        if (obfs != null) 'obfs': obfs,
        if (alpn != null && alpn!.isNotEmpty) 'alpn': alpn,
        if (upMbps != null && upMbps! > 0) 'up_mbps': upMbps,
        if (downMbps != null && downMbps! > 0) 'down_mbps': downMbps,
        if (privateKey != null) 'privateKey': privateKey,
        if (peerPublicKey != null) 'peerPublicKey': peerPublicKey,
        if (localAddress != null) 'localAddress': localAddress,
        if (reserved != null) 'reserved': reserved,
      };

  factory VpnNode.fromJson(Map<String, dynamic> json) {
    return VpnNode(
      id: json['id'] as String,
      type: NodeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NodeType.shadowsocks,
      ),
      name: json['name'] as String,
      server: json['server'] as String,
      port: json['port'] as int,
      method: json['method'] as String?,
      password: json['password'] as String?,
      plugin: json['plugin'] as String?,
      uuid: json['uuid'] as String?,
      security: json['security'] as String?,
      alterId: (json['alterId'] as num?)?.toInt() ?? 0,
      transport: json['transport'] as String?,
      host: json['host'] as String?,
      path: json['path'] as String?,
      tls: json['tls'] as bool? ?? false,
      serverName: json['serverName'] as String?,
      insecure: json['insecure'] as bool? ?? false,
      flow: json['flow'] as String?,
      idleSessionCheckInterval: json['idle_session_check_interval'] as String?,
      idleSessionTimeout: json['idle_session_timeout'] as String?,
      minIdleSession: (json['min_idle_session'] as num?)?.toInt() ?? 0,
      obfs: json['obfs'] as String?,
      alpn: (json['alpn'] as List?)?.map((value) => value.toString()).toList(),
      upMbps: (json['up_mbps'] as num?)?.toInt(),
      downMbps: (json['down_mbps'] as num?)?.toInt(),
      privateKey: json['privateKey'] as String?,
      peerPublicKey: json['peerPublicKey'] as String?,
      localAddress: json['localAddress'] as String?,
      reserved: (json['reserved'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
    );
  }

  /// Verify this node has the minimum required fields to be usable.
  bool get isUsable {
    if (server.isEmpty || port <= 0) return false;
    switch (type) {
      case NodeType.shadowsocks:
        return method != null &&
            method!.isNotEmpty &&
            password != null &&
            password!.isNotEmpty;
      case NodeType.vmess:
      case NodeType.vless:
        return uuid != null && uuid!.isNotEmpty;
      case NodeType.trojan:
        return password != null && password!.isNotEmpty;
      case NodeType.anytls:
      case NodeType.hysteria2:
        return password != null && password!.isNotEmpty;
      case NodeType.wireguard:
        return privateKey != null &&
            privateKey!.isNotEmpty &&
            peerPublicKey != null &&
            peerPublicKey!.isNotEmpty &&
            localAddress != null &&
            localAddress!.isNotEmpty;
    }
  }
}
