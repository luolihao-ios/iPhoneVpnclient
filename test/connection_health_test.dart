import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/connection_health.dart';
import 'package:forge_vpn_flutter/core/singbox_config.dart';

void main() {
  test('系统 TUN 验证只把 HTTP 204 判定为成功', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });

    final result = await verifyThroughSystemTun(
      target: Uri.parse('http://127.0.0.1:${server.port}/generate_204'),
    );

    expect(result.ok, isTrue);
    expect(result.statusCode, HttpStatus.noContent);
    expect(result.error, isNull);
  });

  test('系统 TUN 验证拒绝 HTTP 200', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('ok');
      await request.response.close();
    });

    final result = await verifyThroughSystemTun(
      target: Uri.parse('http://127.0.0.1:${server.port}/generate_204'),
    );

    expect(result.ok, isFalse);
    expect(result.statusCode, HttpStatus.ok);
    expect(result.error, 'unexpected HTTP status 200');
  });

  test('系统 TUN 验证超时后返回失败而不是抛出异常', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {});

    final result = await verifyThroughSystemTun(
      target: Uri.parse('http://127.0.0.1:${server.port}/generate_204'),
      timeout: const Duration(milliseconds: 30),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('timed out'));
  });

  test('桌面验证必须经过本地 HTTP 代理且只接受 204', () async {
    var capturedPort = 0;
    Uri? capturedTarget;
    var capturedTimeout = 0;

    final result = await verifyThroughDesktopProxy(
      requester: ({
        required proxyPort,
        required target,
        required timeoutMs,
      }) async {
        capturedPort = proxyPort;
        capturedTarget = target;
        capturedTimeout = timeoutMs;
        return 'HTTP/1.1 200 OK';
      },
    );

    expect(capturedPort, defaultHttpPort);
    expect(capturedTarget, vpnHealthCheckUri);
    expect(capturedTimeout, 5000);
    expect(result.ok, isFalse);
    expect(result.statusCode, HttpStatus.ok);
  });

  test('桌面代理返回 HTTP 204 时验证成功', () async {
    final result = await verifyThroughDesktopProxy(
      requester: ({
        required proxyPort,
        required target,
        required timeoutMs,
      }) async => 'HTTP/1.1 204 No Content',
    );

    expect(result.ok, isTrue);
    expect(result.statusCode, HttpStatus.noContent);
  });
}
