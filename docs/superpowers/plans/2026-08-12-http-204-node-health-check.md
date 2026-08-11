# HTTP 204 Node Health Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the false-positive HTTP CONNECT check with a real per-node request to `http://www.gstatic.com/generate_204`, accepting only HTTP 204 within a shared three-second budget.

**Architecture:** Each Windows node continues to run in an isolated temporary sing-box process with a local HTTP proxy. The health checker sends an absolute-form HTTP request through that proxy, reads only the response status line, and reports success only for status 204. Existing exhaustive screening, three-worker concurrency, cancellation, cleanup, and mobile TCP checks remain unchanged.

**Tech Stack:** Dart `Socket`, Flutter tests, sing-box temporary configurations, Provider state management, Windows Flutter desktop build.

## Global Constraints

- Test every subscription node; never stop after finding a fixed number of usable nodes.
- Allow at most 3 seconds from temporary sing-box startup through receipt of the HTTP response.
- Use only `http://www.gstatic.com/generate_204` as the Windows validation target.
- Accept only HTTP 204; local `CONNECT 200`, HTTP 200, redirects, client errors, server errors, empty responses, and timeouts are failures.
- Do not query exit IP, load a complete web page, or add YouTube, TLS, or Cloudflare probes.
- Keep mobile TCP availability checks unchanged.
- Preserve user cancellation, completed results, cleanup of child processes/config files, and the unrelated working-tree change in `test/subscription_import_card_test.dart`.

---

### Task 1: Specify the HTTP 204 proxy contract

**Files:**
- Modify: `test/node_health_test.dart`
- Test: `test/node_health_test.dart`

**Interfaces:**
- Consumes: the existing `HealthCheckResult` model and Dart loopback sockets.
- Produces: `bool isHttp204Response(String statusLine)` and `Future<String> requestHttp204ThroughProxy({required int proxyPort, required Uri target, required int timeoutMs})` expectations for Task 2.

- [ ] **Step 1: Replace CONNECT-only assertions with failing 204 classification tests**

```dart
test('only HTTP 204 marks the external probe successful', () {
  expect(isHttp204Response('HTTP/1.1 204 No Content'), isTrue);
  expect(isHttp204Response('HTTP/1.1 200 Connection established'), isFalse);
  expect(isHttp204Response('HTTP/1.1 200 OK'), isFalse);
  expect(isHttp204Response('HTTP/1.1 301 Moved Permanently'), isFalse);
  expect(isHttp204Response('HTTP/1.1 403 Forbidden'), isFalse);
  expect(isHttp204Response('HTTP/1.1 502 Bad Gateway'), isFalse);
  expect(isHttp204Response(''), isFalse);
});
```

- [ ] **Step 2: Add a failing loopback proxy test that verifies the actual request form**

```dart
test('HTTP 204 probe sends an absolute URL through the local proxy', () async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final requestSeen = Completer<String>();
  final serverTask = server.first.then((socket) async {
    final request = await utf8.decoder.bind(socket).first;
    requestSeen.complete(request);
    socket.write('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n');
    await socket.flush();
    await socket.close();
  });

  final response = await requestHttp204ThroughProxy(
    proxyPort: server.port,
    target: Uri.parse('http://www.gstatic.com/generate_204'),
    timeoutMs: 1000,
  );

  expect(response, startsWith('HTTP/1.1 204'));
  expect(await requestSeen, contains(
    'GET http://www.gstatic.com/generate_204 HTTP/1.1\r\n'
    'Host: www.gstatic.com\r\n',
  ));
  await serverTask;
  await server.close();
});
```

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```powershell
flutter test test/node_health_test.dart
```

Expected: compilation fails because `isHttp204Response` and `requestHttp204ThroughProxy` do not exist. This proves the old CONNECT-only implementation cannot satisfy the new contract.

- [ ] **Step 4: Commit the failing specification**

```powershell
git add test/node_health_test.dart
git commit -m "test: require real HTTP 204 node validation"
```

### Task 2: Implement the bounded HTTP 204 probe

**Files:**
- Modify: `lib/core/node_health.dart:70-185`
- Test: `test/node_health_test.dart`

**Interfaces:**
- Consumes: `requestHttp204ThroughProxy`, target URI, local sing-box HTTP proxy port, and the remaining millisecond budget.
- Produces: `isHttp204Response`, a loopback proxy request helper, and `checkNodeAvailability` results targeting `HTTP 204`.

- [ ] **Step 1: Replace the CONNECT classifier with the exact 204 classifier**

```dart
bool isHttp204Response(String statusLine) {
  return RegExp(r'^HTTP/1\.[01] 204\b', caseSensitive: false)
      .hasMatch(statusLine.trimLeft());
}
```

- [ ] **Step 2: Implement the proxy request with one internal timeout budget**

```dart
Future<String> requestHttp204ThroughProxy({
  required int proxyPort,
  required Uri target,
  required int timeoutMs,
}) async {
  if (timeoutMs <= 0) throw TimeoutException('node check timed out');
  final stopwatch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      proxyPort,
      timeout: Duration(milliseconds: timeoutMs),
    );
    final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
    if (remaining <= 0) throw TimeoutException('node check timed out');
    socket.write(
      'GET $target HTTP/1.1\r\n'
      'Host: ${target.host}\r\n'
      'Connection: close\r\n'
      'User-Agent: ForgeVPN-HealthCheck\r\n\r\n',
    );
    await socket.flush();
    return await utf8
        .decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first
        .timeout(Duration(milliseconds: remaining));
  } finally {
    socket?.destroy();
  }
}
```

- [ ] **Step 3: Integrate the request into `checkNodeAvailability`**

Set the defaults and replace the CONNECT call:

```dart
String targetUrl = 'http://www.gstatic.com/generate_204',
String targetLabel = 'HTTP 204',
```

```dart
final response = await requestHttp204ThroughProxy(
  proxyPort: httpPort,
  target: Uri.parse(targetUrl),
  timeoutMs: remainingMs(),
);
if (!isHttp204Response(response)) {
  throw Exception('unexpected health response: ${response.trim()}');
}
```

Delete `_probeHttpConnect`, `isHttpProxyConnectEstablished`, `targetHost`, and `targetPort`. Keep `remainingMs()` so core startup and HTTP response share the same three-second budget. Keep the existing `finally` block that kills the child and deletes its config.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```powershell
flutter test test/node_health_test.dart
```

Expected: all node-health tests pass, including rejection of CONNECT 200 and non-204 responses.

- [ ] **Step 5: Commit the implementation**

```powershell
git add lib/core/node_health.dart test/node_health_test.dart
git commit -m "fix: validate nodes with HTTP 204"
```

### Task 3: Align provider labels, build marker, and documentation

**Files:**
- Modify: `lib/providers/app_provider.dart:570-710`
- Modify: `pubspec.yaml:3`
- Modify: `PROJECT_SUMMARY.md`
- Test: `test/app_provider_screening_test.dart`
- Test: `test/initial_node_screening_test.dart`

**Interfaces:**
- Consumes: `HealthCheckResult.target == 'HTTP 204'` from Task 2.
- Produces: consistent timeout/error results and visible build marker `0.1.2.003` from `version: 0.1.2+3`.

- [ ] **Step 1: Update provider timeout and exception labels**

In both startup screening and manual full checks, replace timeout/fallback `target: 'HTTPS'` with:

```dart
target: 'HTTP 204',
```

Keep both wrapper timeouts at exactly `const Duration(seconds: 3)`.

- [ ] **Step 2: Increment the build marker**

Change:

```yaml
version: 0.1.2+3
```

The existing UI version formatter will display `0.1.2.003`, allowing screenshots to identify this iteration.

- [ ] **Step 3: Document the corrected availability rule**

Add a dated `PROJECT_SUMMARY.md` entry stating:

```markdown
- Windows 节点检测改为通过待测节点请求 `http://www.gstatic.com/generate_204`。
- 仅收到 HTTP 204 才判定可用，修复仅凭本地 CONNECT 200 导致全部节点误报可用的问题。
- 单节点检测继续使用 3 秒总时限，并保留全节点检查与手动停止。
- 构建标记更新为 `0.1.2.003`。
```

- [ ] **Step 4: Run provider and exhaustive-screening regression tests**

Run:

```powershell
flutter test test/node_health_test.dart test/initial_node_screening_test.dart test/app_provider_screening_test.dart test/windows_proxy_service_test.dart
```

Expected: all tests pass; exhaustive screening validates every TCP-reachable candidate and cancellation tests remain green.

- [ ] **Step 5: Commit integration and documentation**

```powershell
git add lib/providers/app_provider.dart pubspec.yaml PROJECT_SUMMARY.md
git commit -m "chore: label HTTP 204 health checks"
```

### Task 4: Final static analysis and Windows build verification

**Files:**
- Verify: `lib/core/node_health.dart`
- Verify: `lib/core/initial_node_screening.dart`
- Verify: `lib/providers/app_provider.dart`
- Verify: `windows/runner/flutter_window.cpp`

**Interfaces:**
- Consumes: the completed implementation from Tasks 1–3.
- Produces: evidence that Dart analysis, regression tests, and the Windows runner build all pass.

- [ ] **Step 1: Run focused static analysis**

Run:

```powershell
flutter analyze lib/core/node_health.dart lib/core/initial_node_screening.dart lib/providers/app_provider.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Run the complete relevant regression group**

Run:

```powershell
flutter test test/node_health_test.dart test/initial_node_screening_test.dart test/app_provider_screening_test.dart test/windows_proxy_service_test.dart
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Build the Windows release executable**

Run:

```powershell
flutter build windows --release
```

Expected: `Built build\windows\x64\runner\Release\forge_vpn_flutter.exe`.

- [ ] **Step 4: Inspect the final diff and working tree**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; `test/subscription_import_card_test.dart` remains outside the feature commits unless separately requested.

- [ ] **Step 5: Record verification without rebuilding the installer**

The executable is sufficient for this iteration's manual node check. Do not run `scripts/build_windows_installer.ps1` unless the user explicitly requests a new installer package.
