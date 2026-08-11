import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:forge_vpn_flutter/core/subscription.dart';

class _SequenceClient extends http.BaseClient {
  _SequenceClient(this.outcomes);

  final List<Object> outcomes;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final outcome = outcomes[requestCount++];
    if (outcome is Exception) throw outcome;
    return outcome as http.StreamedResponse;
  }
}

http.StreamedResponse _response(String body, int statusCode) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    statusCode,
    headers: const {'content-type': 'text/plain; charset=utf-8'},
  );
}

const _validNode =
    'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M=@156.146.38.170:443#US Node';

void main() {
  test('订阅请求遇到临时网络错误会重试两次后成功', () async {
    final diagnostics = <String>[];
    final client = _SequenceClient([
      const SocketException('信号灯超时时间已到'),
      const SocketException('连接被重置'),
      _response(_validNode, 200),
    ]);

    final nodes = await fetchSubscription(
      'https://example.com/sub.txt?token=secret',
      client: client,
      onDiagnostic: diagnostics.add,
    );

    expect(nodes, hasLength(1));
    expect(client.requestCount, 3);
    expect(
      diagnostics.where((line) => line.contains('transient retry')),
      hasLength(2),
    );
    expect(diagnostics.any((line) => line.contains('token=secret')), isFalse);
  });

  test('HTTP 404 不作为临时网络错误重试', () async {
    final client = _SequenceClient([_response('not found', 404)]);

    await expectLater(
      fetchSubscription('https://example.com/missing', client: client),
      throwsException,
    );

    expect(client.requestCount, 1);
  });
}
