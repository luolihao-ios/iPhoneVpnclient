import 'models/node.dart';
import 'node_health.dart';

typedef NodeTcpProbe = Future<int?> Function(VpnNode node);
typedef NodeValidator = Future<HealthCheckResult> Function(VpnNode node);

const initialScreeningQuickWindow = Duration(seconds: 15);
const initialScreeningOverallLimit = Duration(seconds: 45);
const initialScreeningMinimumAvailable = 5;
const initialScreeningTcpConcurrency = 48;
const initialScreeningValidationConcurrency = 3;

class InitialScreeningSummary {
  const InitialScreeningSummary({
    required this.tcpCheckedCount,
    required this.validatedCount,
    required this.availableCount,
    required this.cancelled,
    required this.timedOut,
    required this.exhaustedCandidates,
    required this.reachedMinimumAfterQuickWindow,
  });

  final int tcpCheckedCount;
  final int validatedCount;
  final int availableCount;
  final bool cancelled;
  final bool timedOut;
  final bool exhaustedCandidates;
  final bool reachedMinimumAfterQuickWindow;
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
  DateTime Function()? now,
  Duration quickWindow = initialScreeningQuickWindow,
  Duration overallLimit = initialScreeningOverallLimit,
  int minimumAvailable = initialScreeningMinimumAvailable,
  int tcpConcurrency = initialScreeningTcpConcurrency,
  int validationConcurrency = initialScreeningValidationConcurrency,
}) async {
  final currentTime = now ?? DateTime.now;
  final startedAt = currentTime();
  final candidates = <_TcpCandidate>[];
  var tcpCursor = 0;
  var tcpCheckedCount = 0;
  var validatedCount = 0;
  var availableCount = 0;
  var timedOut = false;
  var reachedMinimumAfterQuickWindow = false;

  bool reachedOverallLimit() {
    return currentTime().difference(startedAt) >= overallLimit;
  }

  final effectiveTcpConcurrency = tcpConcurrency < 1 ? 1 : tcpConcurrency;
  final tcpWorkers = List.generate(
    nodes.length < effectiveTcpConcurrency
        ? nodes.length
        : effectiveTcpConcurrency,
    (_) async {
      while (tcpCursor < nodes.length && !isCancelled()) {
        if (reachedOverallLimit()) {
          timedOut = true;
          return;
        }
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
        final elapsed = currentTime().difference(startedAt);
        if (elapsed >= overallLimit) {
          timedOut = true;
          return;
        }
        if (elapsed >= quickWindow && availableCount >= minimumAvailable) {
          reachedMinimumAfterQuickWindow = true;
          return;
        }

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
    timedOut: timedOut,
    exhaustedCandidates:
        !isCancelled() && !timedOut && validationCursor >= candidates.length,
    reachedMinimumAfterQuickWindow: reachedMinimumAfterQuickWindow,
  );
}
