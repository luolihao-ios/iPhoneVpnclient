import 'models/node.dart';
import 'node_health.dart';

typedef NodeTcpProbe = Future<int?> Function(VpnNode node);
typedef NodeValidator = Future<HealthCheckResult> Function(VpnNode node);

const initialScreeningTcpConcurrency = 48;
const initialScreeningValidationConcurrency = 3;

class InitialScreeningSummary {
  const InitialScreeningSummary({
    required this.tcpCheckedCount,
    required this.validatedCount,
    required this.availableCount,
    required this.cancelled,
    required this.exhaustedCandidates,
  });

  final int tcpCheckedCount;
  final int validatedCount;
  final int availableCount;
  final bool cancelled;
  final bool exhaustedCandidates;
}

class _TcpCandidate {
  const _TcpCandidate(this.node, this.latency);

  final VpnNode node;
  final int latency;
}

Future<InitialScreeningSummary> runInitialNodeScreening({
  required List<VpnNode> nodes,
  required NodeTcpProbe tcpProbe,
  required NodeValidator validate,
  required void Function(VpnNode node) onNodeChecking,
  required void Function(VpnNode node, int latency) onTcpReachable,
  required void Function(VpnNode node, HealthCheckResult result) onNodeResult,
  required bool Function() isCancelled,
  int tcpConcurrency = initialScreeningTcpConcurrency,
  int validationConcurrency = initialScreeningValidationConcurrency,
}) async {
  final candidates = <_TcpCandidate>[];
  var tcpCursor = 0;
  var tcpCheckedCount = 0;
  var validatedCount = 0;
  var availableCount = 0;

  final effectiveTcpConcurrency = tcpConcurrency < 1 ? 1 : tcpConcurrency;
  final tcpWorkers = List.generate(
    nodes.length < effectiveTcpConcurrency
        ? nodes.length
        : effectiveTcpConcurrency,
    (_) async {
      while (tcpCursor < nodes.length && !isCancelled()) {
        final node = nodes[tcpCursor++];
        int? latency;
        try {
          latency = await tcpProbe(node);
        } catch (_) {
          latency = null;
        }
        if (isCancelled()) return;

        tcpCheckedCount++;
        if (latency != null && latency > 0) {
          candidates.add(_TcpCandidate(node, latency));
          onTcpReachable(node, latency);
        } else {
          onNodeResult(
            node,
            const HealthCheckResult(
              ok: false,
              healthStatus: 'unavailable',
              target: 'Node',
              error: 'TCP connection timed out',
            ),
          );
        }
      }
    },
  );
  await Future.wait(tcpWorkers);

  candidates.sort((a, b) => a.latency.compareTo(b.latency));
  var validationCursor = 0;
  final effectiveValidationConcurrency =
      validationConcurrency < 1 ? 1 : validationConcurrency;
  final validationWorkers = List.generate(
    candidates.length < effectiveValidationConcurrency
        ? candidates.length
        : effectiveValidationConcurrency,
    (_) async {
      while (validationCursor < candidates.length && !isCancelled()) {
        final candidate = candidates[validationCursor++];
        final node = candidate.node;
        onNodeChecking(node);

        late HealthCheckResult result;
        try {
          result = await validate(node);
        } catch (error) {
          result = HealthCheckResult(
            ok: false,
            healthStatus: 'unavailable',
            target: 'HTTPS',
            error: error.toString(),
          );
        }
        if (isCancelled()) return;

        validatedCount++;
        if (result.ok && result.latency != null && result.latency! > 0) {
          availableCount++;
        }
        onNodeResult(node, result);
      }
    },
  );
  await Future.wait(validationWorkers);

  return InitialScreeningSummary(
    tcpCheckedCount: tcpCheckedCount,
    validatedCount: validatedCount,
    availableCount: availableCount,
    cancelled: isCancelled(),
    exhaustedCandidates:
        !isCancelled() && validationCursor >= candidates.length,
  );
}
