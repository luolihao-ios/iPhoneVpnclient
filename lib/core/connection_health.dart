import 'dart:async';
import 'dart:io';

import 'dns_fallback_coordinator.dart';
import 'node_health.dart';
import 'singbox_config.dart';

final Uri vpnHealthCheckUri =
    Uri.parse('http://www.gstatic.com/generate_204');

typedef Proxy204Requester = Future<String> Function({
  required int proxyPort,
  required Uri target,
  required int timeoutMs,
});

/// Validate the active mobile system tunnel with a normal device request.
Future<DnsAttemptResult> verifyThroughSystemTun({
  Uri? target,
  Duration timeout = const Duration(seconds: 5),
  HttpClient? client,
}) async {
  final ownsClient = client == null;
  final httpClient = client ?? HttpClient();
  try {
    final request = await httpClient
        .getUrl(target ?? vpnHealthCheckUri)
        .timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    if (response.statusCode == HttpStatus.noContent) {
      return const DnsAttemptResult.passed(statusCode: HttpStatus.noContent);
    }
    return DnsAttemptResult.failed(
      'unexpected HTTP status ${response.statusCode}',
      statusCode: response.statusCode,
    );
  } on TimeoutException {
    return const DnsAttemptResult.failed('HTTP 204 check timed out');
  } catch (error) {
    return DnsAttemptResult.failed(_cleanHealthError(error));
  } finally {
    if (ownsClient) httpClient.close(force: true);
  }
}

/// Validate the desktop connection through sing-box's local HTTP proxy.
Future<DnsAttemptResult> verifyThroughDesktopProxy({
  int proxyPort = defaultHttpPort,
  Duration timeout = const Duration(seconds: 5),
  Proxy204Requester requester = requestHttp204ThroughProxy,
}) async {
  try {
    final statusLine = await requester(
      proxyPort: proxyPort,
      target: vpnHealthCheckUri,
      timeoutMs: timeout.inMilliseconds,
    );
    final statusCode = _statusCode(statusLine);
    if (isHttp204Response(statusLine)) {
      return const DnsAttemptResult.passed(statusCode: HttpStatus.noContent);
    }
    return DnsAttemptResult.failed(
      'unexpected HTTP status ${statusCode ?? 'unknown'}',
      statusCode: statusCode,
    );
  } on TimeoutException {
    return const DnsAttemptResult.failed('HTTP 204 check timed out');
  } catch (error) {
    return DnsAttemptResult.failed(_cleanHealthError(error));
  }
}

int? _statusCode(String statusLine) {
  final match = RegExp(r'^HTTP/1\.[01]\s+(\d{3})\b', caseSensitive: false)
      .firstMatch(statusLine.trimLeft());
  return int.tryParse(match?.group(1) ?? '');
}

String _cleanHealthError(Object error) {
  final text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (text.length <= 160) return text;
  return '${text.substring(0, 157)}...';
}
