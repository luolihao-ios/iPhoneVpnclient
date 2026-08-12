import 'remote_dns.dart';

typedef StartDnsAttempt = Future<void> Function(RemoteDnsProvider provider);
typedef StopDnsAttempt = Future<void> Function();
typedef VerifyDnsAttempt = Future<DnsAttemptResult> Function();

/// Result of validating the current DNS and proxy path.
class DnsAttemptResult {
  const DnsAttemptResult.passed({this.statusCode = 204})
      : ok = true,
        error = null;

  const DnsAttemptResult.failed(this.error, {this.statusCode}) : ok = false;

  final bool ok;
  final int? statusCode;
  final String? error;
}

class DnsFallbackCancelled implements Exception {
  const DnsFallbackCancelled();

  @override
  String toString() => 'DNS fallback cancelled';
}

class AllDnsProvidersFailed implements Exception {
  const AllDnsProvidersFailed(this.message, this.failures);

  final String message;
  final Map<RemoteDnsProvider, String> failures;

  @override
  String toString() => message;
}

/// Runs at most one connection attempt per built-in DNS provider.
class DnsFallbackCoordinator {
  DnsFallbackCoordinator({this.onLog});

  final void Function(String line)? onLog;
  int _generation = 0;

  void cancel() {
    _generation++;
  }

  Future<RemoteDnsProvider> connect({
    required RemoteDnsProvider? preferred,
    required StartDnsAttempt start,
    required StopDnsAttempt stop,
    required VerifyDnsAttempt verify,
  }) async {
    final generation = ++_generation;
    final providers = orderedRemoteDnsProviders(preferred);
    final failures = <RemoteDnsProvider, String>{};

    for (var index = 0; index < providers.length; index++) {
      _ensureActive(generation);
      final provider = providers[index];
      final endpoint = remoteDnsEndpoint(provider);
      _log(
        '[dns-fallback] attempt=${index + 1}/${providers.length} '
        'provider=${endpoint.name}',
      );

      DnsAttemptResult result;
      try {
        await start(provider);
        _ensureActive(generation);
        result = await verify();
        _ensureActive(generation);
      } on DnsFallbackCancelled {
        rethrow;
      } catch (error) {
        result = DnsAttemptResult.failed(_cleanReason(error));
      }

      if (result.ok && result.statusCode == 204) {
        _log(
          '[dns-fallback] provider=${endpoint.name} '
          'result=passed status=204',
        );
        return provider;
      }

      final reason = _cleanReason(
        result.error ?? 'unexpected status ${result.statusCode ?? 'unknown'}',
      );
      failures[provider] = reason;
      _log(
        '[dns-fallback] provider=${endpoint.name} '
        'result=failed reason=$reason',
      );

      try {
        await stop();
      } on DnsFallbackCancelled {
        rethrow;
      } catch (error) {
        _log(
          '[dns-fallback] provider=${endpoint.name} '
          'stop=failed reason=${_cleanReason(error)}',
        );
      }
      _ensureActive(generation);

      if (index + 1 < providers.length) {
        final next = remoteDnsEndpoint(providers[index + 1]);
        _log('[dns-fallback] switching ${endpoint.name} -> ${next.name}');
      }
    }

    _log('[dns-fallback] all providers failed');
    throw AllDnsProvidersFailed(
      '三组远程 DNS/代理链路均不可用，请检查节点或网络',
      Map.unmodifiable(failures),
    );
  }

  void _ensureActive(int generation) {
    if (generation != _generation) throw const DnsFallbackCancelled();
  }

  void _log(String line) {
    onLog?.call(line);
  }
}

String _cleanReason(Object? error) {
  final text = (error?.toString() ?? 'unknown error')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();
  if (text.length <= 160) return text;
  return '${text.substring(0, 157)}...';
}
