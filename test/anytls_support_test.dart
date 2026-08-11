import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';
import 'package:forge_vpn_flutter/core/subscription.dart';

class _RetryingSubscriptionClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('forbidden')),
        403,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(
          utf8.encode('anytls://secret@example.com:443#AnyTLS')),
      200,
      request: request,
    );
  }
}

class _DiagnosticSubscriptionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('''
proxies:
  - name: Demo
    type: anytls
    server: example.com
    port: 443
    password: super-secret
''')),
      200,
      request: request,
      headers: const {'content-type': 'application/yaml; charset=utf-8'},
    );
  }
}

void main() {
  test('resolves a pasted Stash install link to its HTTPS subscription', () {
    final encoded = Uri.encodeComponent('https://example.com/temporary-config');
    expect(
      resolveSubscriptionInput(
          'stash://install-config?url=$encoded&name=AnyTLS'),
      'https://example.com/temporary-config',
    );
  });

  test('parses an AnyTLS URI node', () {
    final node = parseSubscription(
      'anytls://secret@example.com:443?sni=cdn.example.com#AnyTLS',
    ).single;

    expect(node.type, NodeType.anytls);
    expect(node.password, 'secret');
    expect(node.serverName, 'cdn.example.com');
    expect(node.tls, isTrue);
  });

  test('parses AnyTLS JSON and generates its sing-box outbound', () {
    final node = parseSubscription(jsonEncode({
      'type': 'anytls',
      'name': 'AnyTLS JSON',
      'server': 'example.com',
      'server_port': 443,
      'password': 'secret',
      'tls': {'server_name': 'cdn.example.com', 'insecure': true},
      'idle_session_check_interval': '30s',
      'idle_session_timeout': '30s',
      'min_idle_session': 2,
    })).single;

    final config = buildSingBoxConfig(node: node, includeSocks: false);
    final outbound = (config['outbounds'] as List).first as Map;

    expect(outbound['type'], 'anytls');
    expect(outbound['password'], 'secret');
    expect(outbound['min_idle_session'], 2);
    expect((outbound['tls'] as Map)['server_name'], 'cdn.example.com');
  });

  test('parses sing-box JSON outbounds and ignores non-proxy outbounds', () {
    final nodes = parseSubscription(jsonEncode({
      'outbounds': [
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'vless',
          'tag': 'VLESS Reality',
          'server': 'example.com',
          'server_port': 443,
          'uuid': '11111111-1111-1111-1111-111111111111',
          'flow': 'xtls-rprx-vision',
          'tls': {
            'enabled': true,
            'server_name': 'cdn.example.com',
            'insecure': true,
          },
          'transport': {
            'type': 'ws',
            'path': '/edge',
            'headers': {'Host': 'cdn.example.com'},
          },
        },
        {
          'type': 'shadowsocks',
          'tag': 'SS',
          'server': 'ss.example.com',
          'server_port': 8388,
          'method': 'aes-256-gcm',
          'password': 'ss-secret',
        },
      ],
    }));

    expect(nodes, hasLength(2));
    expect(nodes[0].name, 'VLESS Reality');
    expect(nodes[0].serverName, 'cdn.example.com');
    expect(nodes[0].transport, 'ws');
    expect(nodes[0].path, '/edge');
    expect(nodes[1].type, NodeType.shadowsocks);
    expect(nodes[1].method, 'aes-256-gcm');
  });

  test('retries a forbidden subscription request with the FlClash user agent',
      () async {
    final client = _RetryingSubscriptionClient();

    final nodes = await fetchSubscription(
      'https://example.com/temporary-config',
      client: client,
    );

    expect(nodes, hasLength(1));
    expect(client.requests, hasLength(2));
    expect(client.requests.first.headers['User-Agent'], 'ForgeDesktopVPN/0.1');
    expect(client.requests.last.headers['User-Agent'], 'flclash');
  });

  test('reports sanitized subscription response diagnostics', () async {
    final diagnostics = <String>[];

    final nodes = await fetchSubscription(
      'https://example.com/sub.yaml?token=do-not-log',
      client: _DiagnosticSubscriptionClient(),
      onDiagnostic: diagnostics.add,
    );

    expect(nodes, hasLength(1));
    expect(diagnostics.any((line) => line.contains('status=200')), isTrue);
    expect(diagnostics.any((line) => line.contains('contentType=')), isTrue);
    expect(diagnostics.any((line) => line.contains('length=')), isTrue);
    expect(
        diagnostics.any((line) => line.contains('token=do-not-log')), isFalse);
    expect(diagnostics.any((line) => line.contains('super-secret')), isFalse);
    expect(diagnostics.any((line) => line.contains('preview=')), isFalse);
  });

  test('parses AnyTLS from a Clash YAML subscription', () {
    final nodes = parseSubscription('''
proxies:
  - name: AnyTLS YAML
    type: anytls
    server: example.com
    port: 443
    password: secret
    sni: cdn.example.com
    skip-cert-verify: true
''');

    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.anytls);
    expect(nodes.single.serverName, 'cdn.example.com');
    expect(nodes.single.insecure, isTrue);
  });

  test('filters traffic and expiry metadata from subscription nodes', () {
    final nodes = parseSubscription(jsonEncode({
      'proxies': [
        {
          'type': 'anytls',
          'name': '🇭🇰 Hong Kong | 01',
          'server': 'hk.example.com',
          'port': 443,
          'password': 'secret',
        },
        {
          'type': 'anytls',
          'name': 'Traffic Reset: 26 Days Left',
          'server': 'hk.example.com',
          'port': 443,
          'password': 'secret',
        },
        {
          'type': 'anytls',
          'name': 'Expire Date: 2026-10-18',
          'server': 'hk.example.com',
          'port': 443,
          'password': 'secret',
        },
        {
          'type': 'anytls',
          'name': '31.26 GB | 150 GB',
          'server': 'hk.example.com',
          'port': 443,
          'password': 'secret',
        },
      ],
    }));

    expect(nodes, hasLength(1));
    expect(nodes.single.name, '🇭🇰 Hong Kong | 01');
  });

  test('routes common emulator DNS addresses directly', () {
    final config = buildSingBoxConfig(
      node: const VpnNode(
        id: 'hkg-1',
        type: NodeType.anytls,
        name: '🇭🇰 Hong Kong | 01',
        server: 'hk.example.com',
        port: 443,
        password: 'secret',
      ),
      tunEnabled: true,
      includeSocks: false,
    );
    final rules = ((config['route'] as Map)['rules'] as List)
        .cast<Map<String, dynamic>>();

    expect(
      rules,
      contains(
        predicate<Map<String, dynamic>>((rule) {
          final cidrs = (rule['ip_cidr'] as List?)?.cast<String>() ?? const [];
          return rule['outbound'] == 'direct' &&
              cidrs.contains('114.114.114.114/32');
        }),
      ),
    );
  });

  test('uses the responsive local DNS as the default resolver', () {
    final config = buildSingBoxConfig(
      node: const VpnNode(
        id: 'hkg-1',
        type: NodeType.anytls,
        name: '🇭🇰 Hong Kong | 01',
        server: 'hk.example.com',
        port: 443,
        password: 'secret',
      ),
    );
    expect((config['dns'] as Map)['final'], 'local');
  });

  test('uses cached China domain and IP rule sets for smart routing', () {
    final config = buildSingBoxConfig(
      node: const VpnNode(
        id: 'hkg-1',
        type: NodeType.anytls,
        name: 'Hong Kong | 01',
        server: 'hk.example.com',
        port: 443,
        password: 'secret',
      ),
      mode: 'rule',
      tunEnabled: true,
      includeSocks: false,
    );

    final route = (config['route'] as Map).cast<String, dynamic>();
    final ruleSets = (route['rule_set'] as List).cast<Map>();
    expect(
      ruleSets,
      containsAll([
        {
          'tag': 'geosite-cn',
          'type': 'remote',
          'format': 'binary',
          'url':
              'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs',
          'download_detour': 'proxy',
        },
        {
          'tag': 'geoip-cn',
          'type': 'remote',
          'format': 'binary',
          'url':
              'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
          'download_detour': 'proxy',
        },
      ]),
    );

    final routeRules = (route['rules'] as List).cast<Map>();
    expect(
      routeRules,
      containsAll([
        {
          'rule_set': ['geosite-cn'],
          'outbound': 'direct'
        },
        {
          'rule_set': ['geoip-cn'],
          'outbound': 'direct'
        },
      ]),
    );
    expect(
      routeRules.where((rule) => rule.containsKey('domain_suffix')),
      contains(
        predicate<Map>((rule) {
          final domains =
              (rule['domain_suffix'] as List?)?.cast<String>() ?? const [];
          return rule['outbound'] == 'proxy' &&
              domains.contains('app-analytics-services.com') &&
              domains.contains('googleapis.com');
        }),
      ),
    );

    final dns = (config['dns'] as Map).cast<String, dynamic>();
    expect(dns['final'], 'local');
    expect(
      (dns['rules'] as List).cast<Map>(),
      contains(
        predicate<Map>((rule) {
          return rule['rule_set'] is List &&
              (rule['rule_set'] as List)
                  .cast<String>()
                  .contains('geosite-cn') &&
              rule['server'] == 'local';
        }),
      ),
    );
  });

  test('normalizes pasted subscription URLs from mobile clipboards', () {
    expect(
      normalizeSubscriptionInput(
        '\uFEFF\u200B https://example.com/sub\u00A0\r\n',
      ),
      'https://example.com/sub',
    );
  });

  test('normalizes wrapped Stash links without zero-width characters', () {
    expect(
      normalizeSubscriptionInput(
        '\u200Bstash://install-config?url=https%3A%2F%2Fexample.com%2Fsub\u200B',
      ),
      'stash://install-config?url=https%3A%2F%2Fexample.com%2Fsub',
    );
  });
}
