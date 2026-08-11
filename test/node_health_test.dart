import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/node_health.dart';

void main() {
  test('HTTP CONNECT 200 响应表示代理链路已建立', () {
    expect(
      isHttpProxyConnectEstablished(
        'HTTP/1.1 200 Connection established\r\n'
        'Proxy-Agent: sing-box\r\n\r\n',
      ),
      isTrue,
    );
  });

  test('HTTP CONNECT 错误响应不表示代理链路可用', () {
    expect(
      isHttpProxyConnectEstablished(
        'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n',
      ),
      isFalse,
    );
    expect(isHttpProxyConnectEstablished(''), isFalse);
  });
}
