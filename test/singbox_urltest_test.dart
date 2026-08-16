import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';
import 'package:forge_vpn_flutter/core/singbox_urltest.dart';

void main() {
  const first = VpnNode(
    id: 'first node',
    name: 'First',
    type: NodeType.vmess,
    server: 'first.example.com',
    port: 443,
    uuid: '11111111-1111-1111-1111-111111111111',
  );
  const second = VpnNode(
    id: 'second',
    name: 'Second',
    type: NodeType.vless,
    server: 'second.example.com',
    port: 443,
    uuid: '22222222-2222-2222-2222-222222222222',
  );

  test('URLTest 配置一次加载整批节点并开放 Clash API', () {
    final config = buildSingBoxUrlTestConfig(
      nodes: const [first, second],
      apiPort: 19090,
    );
    final outbounds =
        (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final selector = outbounds.singleWhere((item) => item['tag'] == 'proxy');
    final experimental = config['experimental'] as Map<String, dynamic>;

    expect(selector['outbounds'], ['node-first_node', 'node-second']);
    expect(
      (experimental['clash_api'] as Map)['external_controller'],
      '127.0.0.1:19090',
    );
    expect(config.containsKey('inbounds'), isFalse);
  });

  test('Clash API delay 返回值作为节点延迟', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    String request = '';
    server.listen((socket) {
      socket.listen((data) {
        request += utf8.decode(data, allowMalformed: true);
        if (!request.contains('\r\n\r\n')) return;
        final body = jsonEncode({'delay': 283});
        socket.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: ${utf8.encode(body).length}\r\n'
            'Connection: close\r\n\r\n$body');
        socket.close();
      });
    });

    final result = await querySingBoxProxyDelay(
      apiPort: server.port,
      outboundTag: nodeOutboundTag(first),
      timeout: const Duration(seconds: 3),
    );

    expect(result.ok, isTrue);
    expect(result.latency, 283);
    expect(request, contains('/proxies/node-first_node/delay?'));
    expect(request, contains('timeout=3000'));
    expect(request, contains('www.gstatic.com'));
  });

  test('Windows 内置 sing-box 能启动批量 URLTest 配置', () async {
    if (!Platform.isWindows) return;
    final core = File(
      'build${Platform.pathSeparator}windows${Platform.pathSeparator}x64'
      '${Platform.pathSeparator}runner${Platform.pathSeparator}Release'
      '${Platform.pathSeparator}sing-box.exe',
    );
    if (!await core.exists()) return;
    final directory = await Directory.systemTemp.createTemp('forge-urltest-');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final session = await SingBoxUrlTestSession.start(
      nodes: const [first, second],
      corePath: core.absolute.path,
      runtimeDir: directory.path,
    );
    await session.close();
  });
}
