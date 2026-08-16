import 'dart:convert';
import 'models/node.dart';

const int defaultHttpPort = 2080;
const int defaultSocksPort = 2081;
const int defaultApiPort = 9090;

const String _singGeositeCnUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs';
const String _singGeoipCnUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs';

const _foreignDomainOverrides = [
  'google.com',
  'googleapis.com',
  'googlevideo.com',
  'youtube.com',
  'youtubei.googleapis.com',
  'ytimg.com',
  'gstatic.com',
  'ggpht.com',
  'app-analytics-services.com',
];

/// Official binary sing-box rule sets keep China routing current without
/// embedding a large, hand-maintained domain/IP list in the app package.
List<Map<String, dynamic>> _chinaRuleSets() => [
      {
        'tag': 'geosite-cn',
        'type': 'remote',
        'format': 'binary',
        'url': _singGeositeCnUrl,
        'download_detour': 'proxy',
      },
      {
        'tag': 'geoip-cn',
        'type': 'remote',
        'format': 'binary',
        'url': _singGeoipCnUrl,
        'download_detour': 'proxy',
      },
    ];

bool _isIpAddress(String value) {
  if (value.isEmpty) return false;
  return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value) ||
      value.contains(':');
}

/// Stable outbound tag used when a mobile core keeps several candidates alive.
/// The source node id is persisted, so this tag is also stable across a
/// reconnect and can safely be passed to the native Clash API bridge.
String nodeOutboundTag(VpnNode node) {
  final safeId = node.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return 'node-$safeId';
}

Map<String, dynamic> _transport(VpnNode node) {
  if (node.transport == null || node.transport == 'tcp') return const {};
  if (node.transport == 'ws' || node.transport == 'websocket') {
    return {
      'type': 'ws',
      'path': node.path ?? '/',
      if (node.host != null) 'headers': {'Host': node.host},
    };
  }
  if (node.transport == 'grpc') {
    return {
      'type': 'grpc',
      'service_name': node.path ?? '',
    };
  }
  return {'type': node.transport};
}

Map<String, dynamic>? _tls(VpnNode node) {
  if (!node.tls) return null;
  return {
    'enabled': true,
    'server_name': node.serverName ?? node.host ?? node.server,
    'insecure': node.insecure,
    if (node.alpn != null && node.alpn!.isNotEmpty) 'alpn': node.alpn,
  };
}

Map<String, dynamic> _hysteriaServer(VpnNode node) => {
      'server': node.server,
      if (node.serverPorts != null && node.serverPorts!.isNotEmpty)
        'server_ports': node.serverPorts
      else
        'server_port': node.port,
      if (node.hopInterval != null && node.hopInterval!.isNotEmpty)
        'hop_interval': node.hopInterval,
    };

Map<String, dynamic> _nodeToOutbound(VpnNode node, {String tag = 'proxy'}) {
  switch (node.type) {
    case NodeType.shadowsocks:
      return {
        'type': 'shadowsocks',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'method': node.method,
        'password': node.password,
      };

    case NodeType.vmess:
      return {
        'type': 'vmess',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'uuid': node.uuid,
        'security': node.security ?? 'auto',
        'alter_id': node.alterId,
        if (_transport(node).isNotEmpty) 'transport': _transport(node),
        if (_tls(node) != null) 'tls': _tls(node),
      };

    case NodeType.vless:
      return {
        'type': 'vless',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'uuid': node.uuid,
        if (node.flow != null) 'flow': node.flow,
        if (_transport(node).isNotEmpty) 'transport': _transport(node),
        if (_tls(node) != null) 'tls': _tls(node),
      };

    case NodeType.trojan:
      return {
        'type': 'trojan',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'password': node.password,
        'tls': {
          'enabled': true,
          'server_name': node.serverName ?? node.server,
        },
      };

    case NodeType.anytls:
      return {
        'type': 'anytls',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'password': node.password,
        if (node.idleSessionCheckInterval != null)
          'idle_session_check_interval': node.idleSessionCheckInterval,
        if (node.idleSessionTimeout != null)
          'idle_session_timeout': node.idleSessionTimeout,
        if (node.minIdleSession > 0) 'min_idle_session': node.minIdleSession,
        'tls': {
          'enabled': true,
          'server_name': node.serverName ?? node.server,
          'insecure': node.insecure,
          if (node.alpn != null && node.alpn!.isNotEmpty) 'alpn': node.alpn,
        },
      };

    case NodeType.hysteria2:
      return {
        'type': 'hysteria2',
        'tag': tag,
        ..._hysteriaServer(node),
        'password': node.password,
        if (node.upMbps != null && node.upMbps! > 0) 'up_mbps': node.upMbps,
        if (node.downMbps != null && node.downMbps! > 0)
          'down_mbps': node.downMbps,
        if (node.obfs != null && node.obfs!.isNotEmpty)
          'obfs': {
            'type': 'salamander',
            'password': node.obfs,
          },
        'tls': {
          'enabled': true,
          'server_name': node.serverName ?? node.server,
          'insecure': node.insecure,
          if (node.alpn != null && node.alpn!.isNotEmpty) 'alpn': node.alpn,
        },
      };

    case NodeType.hysteria:
      return {
        'type': 'hysteria',
        'tag': tag,
        ..._hysteriaServer(node),
        'auth_str': node.password,
        if (node.upMbps != null && node.upMbps! > 0) 'up_mbps': node.upMbps,
        if (node.downMbps != null && node.downMbps! > 0)
          'down_mbps': node.downMbps,
        if (node.obfs != null && node.obfs!.isNotEmpty) 'obfs': node.obfs,
        'tls': {
          'enabled': true,
          'server_name': node.serverName ?? node.server,
          'insecure': node.insecure,
          if (node.alpn != null && node.alpn!.isNotEmpty) 'alpn': node.alpn,
        },
      };

    case NodeType.wireguard:
      return {
        'type': 'wireguard',
        'tag': tag,
        'server': node.server,
        'server_port': node.port,
        'local_address': [node.localAddress],
        'private_key': node.privateKey,
        'peer_public_key': node.peerPublicKey,
        if (node.preSharedKey != null) 'pre_shared_key': node.preSharedKey,
        if (node.reserved != null) 'reserved': node.reserved,
      };
  }
}

/// Builds a short-lived configuration for verifying one candidate node.
///
/// This deliberately excludes TUN, API, cache, and routing rules from the
/// live VPN profile. The HTTP request made through its loopback inbound can
/// therefore only leave through [node].
Map<String, dynamic> buildSingBoxHealthCheckConfig({
  required VpnNode node,
  required int httpPort,
}) {
  return {
    'log': {'level': 'warn', 'timestamp': true},
    'inbounds': [
      {
        'type': 'http',
        'tag': 'health-http-in',
        'listen': '127.0.0.1',
        'listen_port': httpPort,
      },
    ],
    'outbounds': [
      _nodeToOutbound(node, tag: 'health-proxy'),
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
    ],
    'route': {
      'auto_detect_interface': true,
      'final': 'health-proxy',
    },
  };
}

/// Builds the persistent batch-check configuration used by the desktop
/// Clash-compatible delay API. All candidates live in one core process, so a
/// delay request measures the selected outbound instead of process startup.
Map<String, dynamic> buildSingBoxUrlTestConfig({
  required List<VpnNode> nodes,
  required int apiPort,
}) {
  if (nodes.isEmpty) {
    throw ArgumentError.value(nodes, 'nodes', 'must not be empty');
  }
  final tags = nodes.map(nodeOutboundTag).toList(growable: false);
  return {
    'log': {'level': 'warn', 'timestamp': true},
    'dns': {
      'servers': [
        {
          'type': 'udp',
          'tag': 'local',
          'server': '223.5.5.5',
          'server_port': 53,
        },
      ],
      'final': 'local',
      'strategy': 'prefer_ipv4',
    },
    'outbounds': [
      ...nodes.map(
        (node) => _nodeToOutbound(node, tag: nodeOutboundTag(node)),
      ),
      {
        'type': 'selector',
        'tag': 'proxy',
        'outbounds': tags,
        'default': tags.first,
      },
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
    ],
    'route': {
      'auto_detect_interface': true,
      'default_domain_resolver': {
        'server': 'local',
        'strategy': 'prefer_ipv4',
      },
      'final': 'direct',
    },
    'experimental': {
      'clash_api': {
        'external_controller': '127.0.0.1:$apiPort',
        'secret': '',
      },
    },
  };
}

List<Map<String, dynamic>> _dnsRulesForNode(
  VpnNode? node,
  String mode,
) {
  final rules = <Map<String, dynamic>>[];
  if (node != null && node.server.isNotEmpty && !_isIpAddress(node.server)) {
    rules.add({
      'domain': [node.server],
      'server': 'local',
    });
  }
  if (mode == 'rule') {
    rules.add({
      'rule_set': ['geosite-cn'],
      'server': 'local',
    });
  }
  return rules;
}

/// Build a complete sing-box configuration JSON.
Map<String, dynamic> buildSingBoxConfig({
  required VpnNode node,
  List<VpnNode>? nodes,
  String mode = 'global',
  bool tunEnabled = false,
  int httpPort = defaultHttpPort,
  int socksPort = defaultSocksPort,
  int apiPort = defaultApiPort,
  bool includeSocks = true,
  bool includeApi = true,
  bool cacheFile = true,
  String logLevel = 'info',
}) {
  final candidates = nodes == null || nodes.isEmpty ? <VpnNode>[node] : nodes;
  final includeSelector = nodes != null;
  final outbounds = <Map<String, dynamic>>[
    if (includeSelector) ...[
      ...candidates.map(
        (candidate) => _nodeToOutbound(
          candidate,
          tag: nodeOutboundTag(candidate),
        ),
      ),
      {
        'type': 'selector',
        'tag': 'proxy',
        'outbounds': candidates.map(nodeOutboundTag).toList(growable: false),
        'default': nodeOutboundTag(node),
      },
    ] else
      _nodeToOutbound(node),
    {'type': 'direct', 'tag': 'direct'},
    {'type': 'block', 'tag': 'block'},
  ];

  final inbounds = <Map<String, dynamic>>[
    {
      'type': 'http',
      'tag': 'http-in',
      'listen': '127.0.0.1',
      'listen_port': httpPort,
    },
  ];

  if (includeSocks) {
    inbounds.add({
      'type': 'socks',
      'tag': 'socks-in',
      'listen': '127.0.0.1',
      'listen_port': socksPort,
    });
  }

  if (tunEnabled) {
    inbounds.add({
      'type': 'tun',
      'tag': 'tun-in',
      'interface_name': 'ForgeVPN',
      'address': ['172.19.0.1/30'],
      'auto_route': true,
      'strict_route': true,
      'stack': 'system',
    });
  }

  // sing-box 1.13 removed legacy inbound sniff fields. Keep sniffing as a
  // route action so both the SOCKS and TUN inbounds retain the old behavior.
  final routeRules = <Map<String, dynamic>>[
    {'action': 'sniff'},
    // Android emulators and some apps hard-code these public DNS servers.
    // Keep their UDP DNS packets outside AnyTLS, which may not provide a
    // usable UDP response path for every server.
    {
      'ip_cidr': [
        '114.114.114.114/32',
        '223.5.5.5/32',
      ],
      'outbound': 'direct',
    },
    {'ip_is_private': true, 'outbound': 'direct'},
    if (mode == 'rule')
      {
        'domain_suffix': _foreignDomainOverrides,
        'outbound': 'proxy',
      },
    if (mode == 'rule')
      {
        'rule_set': ['geosite-cn'],
        'outbound': 'direct',
      },
    if (mode == 'rule')
      {
        'rule_set': ['geoip-cn'],
        'outbound': 'direct',
      },
  ];

  final config = <String, dynamic>{
    'log': {
      'level': logLevel,
      'timestamp': true,
    },
    'dns': {
      'servers': [
        {
          'type': 'udp',
          'tag': 'local',
          'server': '223.5.5.5',
          'server_port': 53,
        },
      ],
      'rules': _dnsRulesForNode(node, mode),
      'final': 'local',
      'strategy': 'prefer_ipv4',
    },
    'inbounds': inbounds,
    'outbounds': outbounds,
    'route': {
      'auto_detect_interface': true,
      'default_domain_resolver': {
        'server': 'local',
        'strategy': 'prefer_ipv4',
      },
      'final': mode == 'direct' ? 'direct' : 'proxy',
      'rules': routeRules,
      if (mode == 'rule') 'rule_set': _chinaRuleSets(),
    },
  };

  final experimental = <String, dynamic>{};
  if (cacheFile) {
    experimental['cache_file'] = {'enabled': true};
  }
  if (includeApi) {
    experimental['clash_api'] = {
      'external_controller': '127.0.0.1:$apiPort',
      'secret': '',
    };
  }
  if (experimental.isNotEmpty) {
    config['experimental'] = experimental;
  }

  return config;
}

/// Serialize config to JSON string.
String singBoxConfigToJson(Map<String, dynamic> config) {
  return const JsonEncoder.withIndent('  ').convert(config);
}
