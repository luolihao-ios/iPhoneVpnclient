import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'models/node.dart';
import 'node_grouping.dart';

class SubscriptionError implements Exception {
  final String message;
  const SubscriptionError(this.message);
  @override
  String toString() => message;
}

String _decodeBase64(String input) {
  final clean = input.replaceAll('-', '+').replaceAll('_', '/').trim();
  if (clean.isEmpty || clean.length % 4 == 1) return '';
  try {
    final decoded = utf8.decode(
        base64.decode(clean.padRight((clean.length / 4).ceil() * 4, '=')));
    if (decoded.contains(':') || decoded.contains('{') || decoded.contains('}'))
      return decoded;
    return '';
  } catch (_) {
    return '';
  }
}

String _cryptoId(String value) {
  int hash = 2166136261;
  for (final char in value.codeUnits) {
    hash ^= char;
    hash +=
        (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return 'node-${(hash & 0xFFFFFFFF).toRadixString(16)}';
}

List<String>? _serverPortRanges(Map<String, dynamic> node) {
  final raw = node['server_ports'] ??
      node['server-ports'] ??
      node['ports'];
  if (raw == null) return null;
  final values = raw is List ? raw : raw.toString().split(',');
  final ranges = <String>[];
  for (final value in values) {
    final text = value.toString().trim();
    final match = RegExp(r'^(\d+)\s*[-:]\s*(\d+)$').firstMatch(text);
    if (match != null) {
      ranges.add('${match.group(1)}:${match.group(2)}');
    }
  }
  return ranges.isEmpty ? null : ranges;
}

int _nodePort(Map<String, dynamic> node, {List<String>? serverPorts}) {
  final raw = node['server_port'] ?? node['server-port'] ?? node['port'];
  final port = int.tryParse(raw?.toString() ?? '');
  if (port != null && port > 0) return port;
  final firstRange = serverPorts?.first;
  return int.tryParse(firstRange?.split(':').first ?? '') ?? 0;
}

String? _hopInterval(Map<String, dynamic> node) {
  final raw = node['hop_interval'] ?? node['hop-interval'];
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  return RegExp(r'^\d+$').hasMatch(value) ? '${value}s' : value;
}

VpnNode? _normalizeJsonNode(Map<String, dynamic> node, [int index = 0]) {
  final type =
      (node['type'] ?? node['protocol'] ?? '').toString().toLowerCase();
  final name =
      (node['name'] ?? node['remarks'] ?? node['ps'] ?? '$type-${index + 1}')
          .toString();

  if (type == 'ss' || type == 'shadowsocks') {
    final server = (node['server'] ?? node['address'] ?? '').toString();
    final port = int.tryParse(node['server_port']?.toString() ??
            node['port']?.toString() ??
            '0') ??
        0;
    return VpnNode(
      id: node['nodeId']?.toString() ??
          _cryptoId('shadowsocks:$name:$server:$port'),
      type: NodeType.shadowsocks,
      name: name,
      server: server,
      port: port,
      method: node['method']?.toString() ?? node['cipher']?.toString(),
      password: node['password']?.toString(),
    );
  }

  if (type == 'vmess') {
    final server =
        (node['add'] ?? node['address'] ?? node['server'] ?? '').toString();
    final port = int.tryParse(node['port']?.toString() ?? '0') ?? 0;
    final uuid = (node['id'] ?? node['uuid'] ?? '').toString();
    final transport =
        (node['net'] ?? node['network'] ?? node['transport'] ?? 'tcp')
            .toString();
    return VpnNode(
      id: node['nodeId']?.toString() ??
          _cryptoId('vmess:$name:$server:$port:$uuid:$transport'),
      type: NodeType.vmess,
      name: name,
      server: server,
      port: port,
      uuid: uuid,
      security: node['security']?.toString() ?? 'auto',
      alterId: int.tryParse(
              node['aid']?.toString() ?? node['alterId']?.toString() ?? '0') ??
          0,
      transport: transport,
      host: node['host']?.toString() ?? node['requestHost']?.toString(),
      path: node['path']?.toString(),
      tls: node['tls'] == 'tls' ||
          node['tls'] == true ||
          node['streamSecurity'] == 'tls',
      serverName: node['sni']?.toString() ??
          node['serverName']?.toString() ??
          node['host']?.toString(),
      insecure: node['insecure'] == true ||
          node['insecure'] == 'true' ||
          node['allowInsecure'] == true ||
          node['allowInsecure'] == 'true' ||
          node['allowInsecure'] == 'True',
    );
  }

  if (type == 'vless' || type == 'trojan') {
    final server = (node['server'] ?? node['address'] ?? '').toString();
    final port = int.tryParse(node['port']?.toString() ?? '0') ?? 0;
    final uuid = node['uuid']?.toString() ?? node['id']?.toString() ?? '';
    final password = node['password']?.toString();
    final transport =
        (node['network'] ?? node['transport'] ?? 'tcp').toString();
    return VpnNode(
      id: node['nodeId']?.toString() ??
          _cryptoId(
              '$type:$name:$server:$port:${uuid.isNotEmpty ? uuid : (password ?? '')}'),
      type: type == 'vless' ? NodeType.vless : NodeType.trojan,
      name: name,
      server: server,
      port: port,
      uuid: uuid.isNotEmpty ? uuid : null,
      password: password,
      tls: node['tls'] != false,
      serverName: node['serverName']?.toString() ?? node['sni']?.toString(),
      flow: node['flow']?.toString(),
      transport: transport,
      host: node['host']?.toString() ?? node['requestHost']?.toString(),
      path: node['path']?.toString(),
      insecure: node['insecure'] == true ||
          node['insecure'] == 'true' ||
          node['skip-cert-verify'] == true ||
          node['allowInsecure'] == true ||
          node['allowInsecure'] == 'true',
    );
  }

  if (type == 'anytls' || type == 'any-tls') {
    final server = (node['server'] ?? node['address'] ?? '').toString();
    final port = _nodePort(node);
    final tls = node['tls'] is Map
        ? Map<String, dynamic>.from(node['tls'] as Map)
        : const <String, dynamic>{};
    return VpnNode(
      id: node['nodeId']?.toString() ?? _cryptoId('anytls:$name:$server:$port'),
      type: NodeType.anytls,
      name: name,
      server: server,
      port: port,
      password: node['password']?.toString(),
      tls: node['tls'] != false,
      serverName: node['serverName']?.toString() ??
          node['sni']?.toString() ??
          node['servername']?.toString() ??
          tls['server_name']?.toString() ??
          server,
      insecure: node['insecure'] == true ||
          node['insecure'] == 'true' ||
          node['skip-cert-verify'] == true ||
          node['skip-cert-verify'] == 'true' ||
          tls['insecure'] == true,
      alpn: (node['alpn'] ?? tls['alpn']) is List
          ? ((node['alpn'] ?? tls['alpn']) as List)
              .map((value) => value.toString())
              .toList()
          : (node['alpn'] ?? tls['alpn']) == null
              ? null
              : [(node['alpn'] ?? tls['alpn']).toString()],
      idleSessionCheckInterval: (node['idle_session_check_interval'] ??
              node['idle-session-check-interval'])
          ?.toString(),
      idleSessionTimeout:
          (node['idle_session_timeout'] ?? node['idle-session-timeout'])
              ?.toString(),
      minIdleSession: int.tryParse(
              (node['min_idle_session'] ?? node['min-idle-session'])
                      ?.toString() ??
                  '0') ??
          0,
    );
  }

  if (type == 'hysteria2' || type == 'hy2' || type == 'hysteria') {
    final server = (node['server'] ?? node['address'] ?? '').toString();
    final serverPorts = _serverPortRanges(node);
    final port = _nodePort(node, serverPorts: serverPorts);
    final tls = node['tls'] is Map
        ? Map<String, dynamic>.from(node['tls'] as Map)
        : const <String, dynamic>{};
    final obfs = node['obfs'];
    final obfsPassword = type == 'hysteria'
        ? (obfs is Map
            ? obfs['password']?.toString()
            : obfs?.toString() ??
                node['obfs-password']?.toString() ??
                node['obfs_password']?.toString())
        : (obfs is Map
            ? obfs['password']?.toString()
            : node['obfs-password']?.toString() ??
                node['obfs_password']?.toString() ??
                node['obfsPassword']?.toString() ??
                (obfs?.toString().toLowerCase() == 'salamander'
                    ? null
                    : obfs?.toString()));
    final alpn = node['alpn'] ?? tls['alpn'];
    return VpnNode(
      id: node['nodeId']?.toString() ??
          _cryptoId('$type:$name:$server:$port'),
      type: type == 'hysteria' ? NodeType.hysteria : NodeType.hysteria2,
      name: name,
      server: server,
      port: port,
      password: type == 'hysteria'
          ? (node['auth_str'] ?? node['auth-str'] ?? node['password'])
              ?.toString()
          : node['password']?.toString(),
      tls: node['tls'] != false,
      serverName: node['serverName']?.toString() ??
          node['sni']?.toString() ??
          tls['server_name']?.toString() ??
          server,
      insecure: node['insecure'] == true ||
          node['insecure'] == 'true' ||
          node['skip-cert-verify'] == true ||
          tls['insecure'] == true,
      alpn: alpn is List
          ? alpn.map((value) => value.toString()).toList()
          : alpn == null || alpn.toString().trim().isEmpty
              ? null
              : [alpn.toString()],
      obfs: obfsPassword?.trim().isEmpty ?? true ? null : obfsPassword,
      upMbps: int.tryParse(
        (node['up_mbps'] ?? node['up'])?.toString() ?? '',
      ),
      downMbps: int.tryParse(
        (node['down_mbps'] ?? node['down'])?.toString() ?? '',
      ),
      serverPorts: serverPorts,
      hopInterval: _hopInterval(node),
    );
  }

  if (type == 'wireguard') {
    final server = (node['server'] ?? node['address'] ?? '').toString();
    final port = int.tryParse(node['port']?.toString() ?? '51820') ?? 51820;
    return VpnNode(
      id: node['nodeId']?.toString() ??
          _cryptoId(
              'wireguard:$name:$server:$port:${node['peerPublicKey'] ?? node['public_key'] ?? ''}'),
      type: NodeType.wireguard,
      name: name,
      server: server,
      port: port,
      privateKey:
          node['privateKey']?.toString() ?? node['private_key']?.toString(),
      peerPublicKey:
          node['peerPublicKey']?.toString() ?? node['public_key']?.toString(),
      preSharedKey: node['preSharedKey']?.toString() ??
          node['pre_shared_key']?.toString(),
      localAddress:
          node['localAddress']?.toString() ?? node['local_address']?.toString(),
      reserved: (node['reserved'] as List?)?.cast<int>(),
    );
  }

  return null;
}

bool _singBoxTlsEnabled(dynamic value) {
  if (value is Map) return value['enabled'] != false;
  return value == true;
}

Map<String, dynamic> _singBoxOutboundToNode(Map<String, dynamic> outbound) {
  final tls = outbound['tls'] is Map
      ? Map<String, dynamic>.from(outbound['tls'] as Map)
      : const <String, dynamic>{};
  final transport = outbound['transport'] is Map
      ? Map<String, dynamic>.from(outbound['transport'] as Map)
      : const <String, dynamic>{};
  final headers = transport['headers'] is Map
      ? Map<String, dynamic>.from(transport['headers'] as Map)
      : const <String, dynamic>{};
  final localAddress = outbound['local_address'];

  return <String, dynamic>{
    ...outbound,
    'name': outbound['tag'] ?? outbound['name'],
    'port': outbound['server_port'] ?? outbound['port'],
    'server_ports': outbound['server_ports'],
    'hop_interval': outbound['hop_interval'],
    'auth_str': outbound['auth_str'],
    'alterId': outbound['alter_id'] ?? outbound['alterId'],
    'tls': _singBoxTlsEnabled(outbound['tls']),
    'serverName': outbound['server_name'] ??
        tls['server_name'] ??
        tls['servername'] ??
        outbound['sni'],
    'insecure': outbound['insecure'] ?? tls['insecure'] ?? false,
    'alpn': outbound['alpn'] ?? tls['alpn'],
    'obfs': outbound['obfs'] is Map
        ? (outbound['obfs'] as Map)['password']
        : outbound['obfs'],
    'transport': transport['type'] ?? outbound['network'],
    'path': transport['path'] ?? transport['service_name'] ?? outbound['path'],
    'host': headers['Host'] ?? headers['host'] ?? outbound['host'],
    'localAddress': localAddress is List && localAddress.isNotEmpty
        ? localAddress.first
        : localAddress,
  };
}

List<VpnNode> _parseSingBoxJson(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) {
    throw const SubscriptionError('Invalid sing-box subscription format');
  }

  final nodes = outbounds
      .whereType<Map>()
      .map((outbound) => _singBoxOutboundToNode(
            Map<String, dynamic>.from(outbound),
          ))
      .map(_normalizeJsonNode)
      .where((node) => node != null)
      .cast<VpnNode>()
      .toList();
  if (nodes.isEmpty) {
    throw const SubscriptionError(
        'No supported proxy nodes in sing-box subscription');
  }
  return nodes;
}

List<VpnNode> _parseJsonSubscription(String text) {
  final value = json.decode(text);
  if (value is List) {
    return value
        .map((n) => _normalizeJsonNode(n as Map<String, dynamic>))
        .where((n) => n != null)
        .cast<VpnNode>()
        .toList();
  }
  if (value is! Map)
    throw const SubscriptionError('Invalid subscription format');

  final map = value as Map<String, dynamic>;
  if (map['outbounds'] is List) {
    return _parseSingBoxJson(map);
  }
  final msg = map['msg'] ?? map['message'] ?? map['error'] ?? map['detail'];
  if (msg != null && msg.toString().isNotEmpty) {
    final hasNodes = [
      map['nodes'],
      map['proxies'],
      map['servers'],
      map['vmess'],
      map['shadowsocks'],
      map['anytls'],
      map['wireguard'],
    ].any((v) => v is List && v.isNotEmpty);
    if (!hasNodes) throw SubscriptionError(msg.toString());
  }

  // Some providers return one node as a JSON object instead of wrapping it in
  // a `nodes`/`proxies` list. Treat that object as a single subscription node.
  if (map['type'] != null || map['protocol'] != null) {
    final node = _normalizeJsonNode(map);
    if (node != null) return [node];
  }

  for (final key in ['vmess', 'shadowsocks', 'anytls', 'wireguard']) {
    if (map[key] is List) {
      return (map[key] as List)
          .map((n) {
            final node = Map<String, dynamic>.from(n as Map);
            node['type'] = key;
            return _normalizeJsonNode(node);
          })
          .where((n) => n != null)
          .cast<VpnNode>()
          .toList();
    }
  }

  final nodes = map['nodes'] ?? map['proxies'] ?? map['servers'];
  if (nodes is List) {
    return nodes
        .map((n) => _normalizeJsonNode(n as Map<String, dynamic>))
        .where((n) => n != null)
        .cast<VpnNode>()
        .toList();
  }

  throw const SubscriptionError('No nodes found in subscription');
}

dynamic _yamlToDart(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _yamlToDart(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_yamlToDart).toList();
  }
  return value;
}

String _formatTypeCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return '{${keys.map((key) => '$key:${counts[key]}').join(', ')}}';
}

List<VpnNode> _parseClashYaml(
  String text, {
  void Function(String message)? onDiagnostic,
}) {
  final document = loadYaml(text);
  final normalized = _yamlToDart(document);
  if (normalized is! Map) {
    throw const SubscriptionError('Invalid Clash subscription format');
  }

  final proxies = normalized['proxies'];
  if (proxies is! List) {
    throw const SubscriptionError('No nodes found in Clash subscription');
  }

  final sourceCounts = <String, int>{};
  final acceptedCounts = <String, int>{};
  final skippedCounts = <String, int>{};
  final nodes = <VpnNode>[];
  for (final proxy in proxies.whereType<Map>()) {
    final normalizedProxy = Map<String, dynamic>.from(proxy);
    final sourceType =
        (normalizedProxy['type'] ?? normalizedProxy['protocol'] ?? 'unknown')
            .toString()
            .toLowerCase();
    sourceCounts[sourceType] = (sourceCounts[sourceType] ?? 0) + 1;
    final node = _normalizeJsonNode(normalizedProxy, nodes.length);
    if (node == null) {
      skippedCounts[sourceType] = (skippedCounts[sourceType] ?? 0) + 1;
      continue;
    }
    acceptedCounts[node.type.name] = (acceptedCounts[node.type.name] ?? 0) + 1;
    nodes.add(node);
  }
  final fingerprint = _cryptoId(text).replaceFirst('node-', '');
  onDiagnostic?.call(
    'subscription parse summary: bytes=${utf8.encode(text).length} '
    'fingerprint=$fingerprint source=${_formatTypeCounts(sourceCounts)} '
    'accepted=${_formatTypeCounts(acceptedCounts)} '
    'skipped=${_formatTypeCounts(skippedCounts)}',
  );
  return nodes;
}

VpnNode? _parseSsUri(String uri) {
  final withoutScheme = uri.substring('ss://'.length);
  final fragmentIndex = withoutScheme.indexOf('#');
  final main = fragmentIndex >= 0
      ? withoutScheme.substring(0, fragmentIndex)
      : withoutScheme;
  final rawName = fragmentIndex >= 0
      ? withoutScheme.substring(fragmentIndex + 1)
      : 'Shadowsocks';
  final decodedName = _decodeNodeName(rawName);
  final queryParts = main.split('?');
  final userinfoRaw = queryParts[0];
  final queryRaw = queryParts.length > 1 ? queryParts[1] : '';

  final decodedWhole =
      !userinfoRaw.contains('@') ? _decodeBase64(userinfoRaw) : '';
  final source = decodedWhole.isNotEmpty ? decodedWhole : userinfoRaw;
  final atParts =
      source.contains('@') ? source.split('@') : userinfoRaw.split('@');
  final encodedPart = atParts.length > 0 ? atParts[0] : '';
  final userinfo =
      encodedPart.contains(':') ? encodedPart : _decodeBase64(encodedPart);
  if (userinfo.isEmpty) return null;

  final colonIdx = userinfo.indexOf(':');
  if (colonIdx < 0) return null;
  final method = userinfo.substring(0, colonIdx);
  final password = userinfo.substring(colonIdx + 1);
  final target = atParts.length > 1 ? atParts[1] : '';
  final targetParts = target.split(':');
  if (targetParts.length < 2) return null;

  final port = int.tryParse(targetParts[1]) ?? 0;
  final params = Uri.splitQueryString(queryRaw);

  return VpnNode(
    id: _cryptoId(uri),
    type: NodeType.shadowsocks,
    name: decodedName,
    server: targetParts[0],
    port: port,
    method: method,
    password: password,
    plugin: params['plugin'],
  );
}

String _decodeNodeName(String rawName) {
  if (!rawName.contains('%')) return rawName;
  try {
    return Uri.decodeComponent(rawName);
  } on FormatException {
    return rawName;
  } on ArgumentError {
    return rawName;
  }
}

VpnNode? _parseVmessUri(String uri) {
  final decoded = _decodeBase64(uri.substring('vmess://'.length));
  if (decoded.isEmpty) return null;
  final node = json.decode(decoded) as Map<String, dynamic>;
  node['type'] = 'vmess';
  return _normalizeJsonNode(node);
}

VpnNode? _parseUrlNode(String uri, NodeType type) {
  final parsed = Uri.parse(uri);
  final params = parsed.queryParameters;
  final name = Uri.decodeComponent(parsed.fragment.isNotEmpty
      ? parsed.fragment
      : '${type.name}-${parsed.host}');

  if (type == NodeType.vless) {
    return VpnNode(
      id: _cryptoId(uri),
      type: type,
      name: name,
      server: parsed.host,
      port: parsed.port,
      uuid: parsed.userInfo,
      tls: params['security'] == 'tls' || params['security'] == 'reality',
      serverName: params['sni'] ?? params['peer'] ?? parsed.host,
      flow: params['flow'],
      transport: params['type'] ?? 'tcp',
      path: params['path'],
      host: params['host'],
    );
  }

  if (type == NodeType.anytls) {
    final params = parsed.queryParameters;
    return VpnNode(
      id: _cryptoId(uri),
      type: type,
      name: name,
      server: parsed.host,
      port: parsed.port,
      password: parsed.userInfo.isNotEmpty
          ? Uri.decodeComponent(parsed.userInfo)
          : params['password'],
      tls: true,
      serverName: params['sni'] ?? parsed.host,
      insecure: params['insecure'] == '1' || params['insecure'] == 'true',
      idleSessionCheckInterval: params['idle_session_check_interval'],
      idleSessionTimeout: params['idle_session_timeout'],
      minIdleSession: int.tryParse(params['min_idle_session'] ?? '0') ?? 0,
    );
  }

  return VpnNode(
    id: _cryptoId(uri),
    type: type,
    name: name,
    server: parsed.host,
    port: parsed.port,
    password: parsed.userInfo,
    tls: true,
    serverName: params['sni'] ?? parsed.host,
  );
}

VpnNode? _parseLine(String line) {
  final text = line.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('ss://')) return _parseSsUri(text);
  if (text.startsWith('vmess://')) return _parseVmessUri(text);
  if (text.startsWith('vless://')) return _parseUrlNode(text, NodeType.vless);
  if (text.startsWith('trojan://')) return _parseUrlNode(text, NodeType.trojan);
  if (text.startsWith('anytls://')) return _parseUrlNode(text, NodeType.anytls);
  return null;
}

List<VpnNode> _parseUriLines(
  String text, {
  void Function(String message)? onDiagnostic,
}) {
  final nodes = <VpnNode>[];
  var skipped = 0;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    final isSupportedUri = trimmed.startsWith('ss://') ||
        trimmed.startsWith('vmess://') ||
        trimmed.startsWith('vless://') ||
        trimmed.startsWith('trojan://') ||
        trimmed.startsWith('anytls://');
    try {
      final node = _parseLine(trimmed);
      if (node != null && node.isUsable) {
        nodes.add(node);
      } else if (isSupportedUri) {
        skipped++;
      }
    } catch (_) {
      if (isSupportedUri) skipped++;
    }
  }
  onDiagnostic?.call(
    'subscription URI parsing: parsed=${nodes.length} skipped=$skipped',
  );
  return nodes;
}

/// Resolve a pasted subscription URL or an app-specific install wrapper.
String normalizeSubscriptionInput(String input) {
  return input
      .replaceAll('\uFEFF', '')
      .replaceAll('\u200B', '')
      .replaceAll('\u200C', '')
      .replaceAll('\u200D', '')
      .replaceAll('\u2060', '')
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u3000', ' ')
      .trim();
}

String? resolveSubscriptionInput(String input) {
  final text = normalizeSubscriptionInput(input);
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == 'http' || uri.scheme == 'https') return text;
  if (uri.scheme.toLowerCase() == 'stash' &&
      (uri.host == 'install-config' || uri.path == '/install-config')) {
    final url = uri.queryParameters['url'];
    if (url != null &&
        (url.startsWith('http://') || url.startsWith('https://'))) {
      return url;
    }
  }
  return null;
}

List<VpnNode> _dedupeNodes(List<VpnNode> nodes) {
  final seen = <String>{};
  return nodes.where((n) {
    final key = n.id;
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

List<VpnNode> _filterSubscriptionMetadata(List<VpnNode> nodes) {
  return nodes.where((node) => !isSubscriptionMetadataName(node.name)).toList();
}

/// Parse raw subscription text and return list of nodes.
List<VpnNode> parseSubscription(
  String rawText, {
  void Function(String message)? onDiagnostic,
}) {
  final source = rawText.trim();
  if (source.isEmpty) return [];

  final decodedCandidate = _decodeBase64(source);
  final decoded = decodedCandidate.isNotEmpty &&
          (decodedCandidate.contains('://') ||
              decodedCandidate.startsWith('{') ||
              decodedCandidate.startsWith('['))
      ? decodedCandidate
      : '';
  final candidates = [source, decoded].where((s) => s.isNotEmpty).toList();

  for (final candidate in candidates) {
    if (RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(candidate)) {
      try {
        final yamlNodes = _parseClashYaml(
          candidate,
          onDiagnostic: onDiagnostic,
        );
        if (yamlNodes.isNotEmpty) {
          return _dedupeNodes(_filterSubscriptionMetadata(yamlNodes));
        }
      } on SubscriptionError {
        // Continue with the other supported subscription formats.
      } catch (_) {
        // Continue with JSON and line-based parsing.
      }
    }
    try {
      return _filterSubscriptionMetadata(_parseJsonSubscription(candidate));
    } on SubscriptionError {
      rethrow;
    } catch (_) {
      // Continue with line-based parsing
    }
  }

  final nodes = _parseUriLines(
    decoded.isNotEmpty ? decoded : source,
    onDiagnostic: onDiagnostic,
  );
  return _dedupeNodes(_filterSubscriptionMetadata(nodes));
}

String _diagnosticUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return '<invalid-url>';
  return uri.replace(query: '', fragment: '').toString();
}

String _redactSubscriptionPreview(String text) {
  var preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  preview = preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
  return preview.replaceAllMapped(
    RegExp(
      r'(password|passwd|uuid|id|token|secret|private[_-]?key)\s*[:=]\s*[^,}\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
}

Future<http.Response> _requestSubscriptionOnce(
  http.Client client,
  Uri uri,
  String rawUrl,
  void Function(String message)? onDiagnostic,
) async {
  final response = await client.get(uri, headers: {
    'User-Agent': 'ForgeDesktopVPN/0.1',
    'Accept': 'text/plain, application/json, */*',
  });
  onDiagnostic?.call(
    'subscription response: url=${_diagnosticUrl(rawUrl)} '
    'status=${response.statusCode} contentType=${response.headers['content-type'] ?? '<none>'}',
  );

  // Some subscription endpoints only allow known proxy clients. FlClash
  // sends this identity and commonly receives Clash YAML in response.
  var effectiveResponse = response;
  if (effectiveResponse.statusCode == 403 ||
      (effectiveResponse.statusCode == 200 &&
          effectiveResponse.bodyBytes.isEmpty)) {
    effectiveResponse = await client.get(uri, headers: {
      'User-Agent': 'flclash',
      'Accept': 'application/yaml, text/yaml, text/plain, */*',
      'Cache-Control': 'no-cache',
    });
    onDiagnostic?.call(
      'subscription retry: url=${_diagnosticUrl(rawUrl)} '
      'status=${effectiveResponse.statusCode} userAgent=flclash',
    );
  }
  if (effectiveResponse.statusCode == 403 ||
      (effectiveResponse.statusCode == 200 &&
          effectiveResponse.bodyBytes.isEmpty)) {
    // Keep a browser fallback for endpoints that permit browsers instead.
    effectiveResponse = await client.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cache-Control': 'no-cache',
    });
    onDiagnostic?.call(
      'subscription retry: url=${_diagnosticUrl(rawUrl)} '
      'status=${effectiveResponse.statusCode} userAgent=browser',
    );
  }
  return effectiveResponse;
}

bool _isTransientSubscriptionError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;
}

Future<http.Response> _requestSubscriptionWithRetry(
  http.Client client,
  Uri uri,
  String rawUrl,
  void Function(String message)? onDiagnostic,
) async {
  const maxRetries = 2;
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await _requestSubscriptionOnce(
        client,
        uri,
        rawUrl,
        onDiagnostic,
      );
    } catch (error) {
      if (!_isTransientSubscriptionError(error) || attempt == maxRetries) {
        rethrow;
      }
      onDiagnostic?.call(
        'subscription transient retry: url=${_diagnosticUrl(rawUrl)} '
        'attempt=${attempt + 1}/$maxRetries '
        'error=${_redactSubscriptionPreview(error.toString())}',
      );
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }
  throw StateError('subscription retry loop ended unexpectedly');
}

/// Fetch subscription from a URL.
Future<List<VpnNode>> fetchSubscription(String url,
    {http.Client? client, void Function(String message)? onDiagnostic}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse(url);
    final effectiveResponse =
        await _requestSubscriptionWithRetry(c, uri, url, onDiagnostic);

    if (effectiveResponse.statusCode != 200) {
      if (effectiveResponse.statusCode == 403) {
        throw Exception(
          'Subscription request failed: HTTP 403 (link expired or server rejected the client)',
        );
      }
      throw Exception(
          'Subscription request failed: HTTP ${effectiveResponse.statusCode}');
    }
    final bodyBytes = effectiveResponse.bodyBytes;
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    onDiagnostic?.call(
      'subscription body: url=${_diagnosticUrl(url)} '
      'status=${effectiveResponse.statusCode} '
      'contentType=${effectiveResponse.headers['content-type'] ?? '<none>'} '
      'length=${bodyBytes.length}',
    );
    try {
      final nodes = parseSubscription(body, onDiagnostic: onDiagnostic);
      onDiagnostic?.call('subscription parsed: nodes=${nodes.length}');
      if (nodes.isEmpty) {
        throw const SubscriptionError(
          'Subscription returned no supported proxy nodes',
        );
      }
      return nodes;
    } catch (error) {
      onDiagnostic?.call('subscription parse failed: $error');
      rethrow;
    }
  } catch (error) {
    onDiagnostic?.call(
      'subscription request failed: url=${_diagnosticUrl(url)} '
      'error=${_redactSubscriptionPreview(error.toString())}',
    );
    rethrow;
  } finally {
    if (client == null) c.close();
  }
}
