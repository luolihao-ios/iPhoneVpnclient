import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/node_health.dart';

void main() {
  test('只有 HTTP 204 响应表示节点真实可用', () {
    expect(isHttp204Response('HTTP/1.1 204 No Content'), isTrue);
    expect(isHttp204Response('HTTP/1.0 204 No Content'), isTrue);
    expect(
      isHttp204Response('HTTP/1.1 200 Connection established'),
      isFalse,
    );
    expect(isHttp204Response('HTTP/1.1 200 OK'), isFalse);
    expect(isHttp204Response('HTTP/1.1 301 Moved Permanently'), isFalse);
    expect(isHttp204Response('HTTP/1.1 403 Forbidden'), isFalse);
    expect(isHttp204Response('HTTP/1.1 502 Bad Gateway'), isFalse);
    expect(isHttp204Response(''), isFalse);
  });

  test('HTTP 204 检测通过本地代理发送绝对地址请求', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final requestSeen = Completer<String>();
    final serverTask = server.first.then((socket) async {
      final requestBytes = <int>[];
      final headerComplete = Completer<String>();
      final subscription = socket.listen((data) {
        requestBytes.addAll(data);
        final request = utf8.decode(requestBytes);
        if (request.contains('\r\n\r\n') && !headerComplete.isCompleted) {
          headerComplete.complete(request);
        }
      });
      final request = await headerComplete.future;
      requestSeen.complete(request);
      socket.write(
        'HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n',
      );
      await socket.flush();
      await socket.close();
      await subscription.cancel();
    });

    final response = await requestHttp204ThroughProxy(
      proxyPort: server.port,
      target: Uri.parse('http://www.gstatic.com/generate_204'),
      timeoutMs: 1000,
    );

    expect(response, startsWith('HTTP/1.1 204'));
    expect(
      await requestSeen,
      contains(
        'GET http://www.gstatic.com/generate_204 HTTP/1.1\r\n'
        'Host: www.gstatic.com',
      ),
    );
    await serverTask;
    await server.close();
  });
}
