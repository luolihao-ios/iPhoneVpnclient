# Full Node Connectivity and Proxy Shutdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check every imported node through a lightweight proxy handshake within three seconds and restore Forge-owned Windows proxy settings during shutdown or restart.

**Architecture:** Desktop health checks will launch an isolated sing-box process and issue an HTTP `CONNECT` request through its local proxy to `www.youtube.com:443`; a `200` response header establishes availability without loading content or querying IP geolocation. The initial screen worker will validate every node with existing cancellation and three-way concurrency. The Windows runner will restore proxy settings on session-end messages as well as normal tray exit and startup recovery.

**Tech Stack:** Flutter/Dart, sing-box CLI, Win32 registry APIs, Flutter test.

## Global Constraints

- Desktop node validation has a three-second total timeout per node.
- All imported nodes are checked; no available-node quota or batch time limit may stop the run.
- Preserve three concurrent checks and the existing Stop action.
- Do not delete another application's disabled `ProxyServer` value.

---

### Task 1: Validate a proxy CONNECT response without loading a page

**Files:**
- Modify: `lib/core/node_health.dart`
- Create: `test/node_health_test.dart`

**Interfaces:**
- Produces `bool isHttpProxyConnectEstablished(String response)`.
- `checkNodeAvailability` uses the helper after opening a local proxy socket.

- [ ] **Step 1: Write the failing test**

```dart
test('CONNECT 200 response marks proxy handshake as established', () {
  expect(
    isHttpProxyConnectEstablished(
      'HTTP/1.1 200 Connection established\\r\\n\\r\\n',
    ),
    isTrue,
  );
  expect(isHttpProxyConnectEstablished('HTTP/1.1 502 Bad Gateway\\r\\n'), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/node_health_test.dart`

Expected: FAIL because `isHttpProxyConnectEstablished` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
bool isHttpProxyConnectEstablished(String response) {
  return RegExp(r'^HTTP/1\\.[01] 200\\b').hasMatch(response);
}
```

Replace the geo-IP curl loop with a local socket request to the temporary proxy. Send `CONNECT www.youtube.com:443 HTTP/1.1`, read only through the end of response headers, and return success as soon as the helper accepts the status. Bound startup and handshake work by the remaining portion of `timeoutMs`; do not call `tcpPing` after success.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/node_health_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/node_health.dart test/node_health_test.dart
git commit -m "feat: use proxy handshake for node health"
```

### Task 2: Make automatic screening validate every node

**Files:**
- Modify: `lib/core/initial_node_screening.dart`
- Modify: `lib/providers/app_provider.dart`
- Modify: `test/initial_node_screening_test.dart`

**Interfaces:**
- `runInitialNodeScreening` invokes `validate` for every supplied node until cancellation.
- `AppProvider.startInitialNodeScreening` uses a three-second `_awaitNodeCheck` timeout.

- [ ] **Step 1: Write the failing test**

```dart
test('available nodes do not stop full screening early', () async {
  final nodes = List.generate(8, _node);
  final validated = <String>[];
  await runInitialNodeScreening(
    nodes: nodes,
    validationConcurrency: 1,
    tcpProbe: (_) async => 10,
    validate: (node) async {
      validated.add(node.id);
      return _available;
    },
    onNodeChecking: (_) {},
    onTcpReachable: (_, __) {},
    onNodeResult: (_, __) {},
    isCancelled: () => false,
  );
  expect(validated, nodes.map((node) => node.id));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/initial_node_screening_test.dart --plain-name "available nodes do not stop full screening early"`

Expected: FAIL because the quick-window quota stops validation.

- [ ] **Step 3: Write minimal implementation**

Remove the quick-window, minimum-available, and overall-limit exit branches. Keep TCP pre-screening for fast rejection, validate all TCP-reachable candidates with three workers, and keep cancellation checks before each new task. Change automatic and manual full-check wrapper timeouts from ten seconds to three seconds.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/initial_node_screening_test.dart test/app_provider_screening_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/initial_node_screening.dart lib/providers/app_provider.dart test/initial_node_screening_test.dart test/app_provider_screening_test.dart
git commit -m "feat: fully verify all subscription nodes"
```

### Task 3: Restore Forge proxy during Windows session shutdown

**Files:**
- Modify: `windows/runner/flutter_window.cpp`
- Modify: `test/windows_proxy_service_test.dart`

**Interfaces:**
- `FlutterWindow::MessageHandler` calls `RestoreForgeProxySync()` for `WM_QUERYENDSESSION` and `WM_ENDSESSION`.
- Existing tray exit and next-start recovery remain intact.

- [ ] **Step 1: Write the failing test**

Add a source-level guard test that requires both `WM_QUERYENDSESSION` and `WM_ENDSESSION` handling and a synchronous call to `RestoreForgeProxySync` in `windows/runner/flutter_window.cpp`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/windows_proxy_service_test.dart`

Expected: FAIL because the runner does not handle session-end messages.

- [ ] **Step 3: Write minimal implementation**

```cpp
if (message == WM_QUERYENDSESSION || message == WM_ENDSESSION) {
  RestoreForgeProxySync();
}
```

Keep `ProxyServer` untouched when `ProxyEnable` is already zero, so a disabled proxy setting from another application survives.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/windows_proxy_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/runner/flutter_window.cpp test/windows_proxy_service_test.dart
git commit -m "fix: restore Forge proxy on Windows shutdown"
```

### Task 4: Verify and document the combined behavior

**Files:**
- Modify: `PROJECT_SUMMARY.md`

- [ ] **Step 1: Run focused validation**

Run:

```bash
flutter test test/node_health_test.dart test/initial_node_screening_test.dart test/app_provider_screening_test.dart test/windows_proxy_service_test.dart
flutter analyze lib/core/node_health.dart lib/core/initial_node_screening.dart lib/providers/app_provider.dart
```

Expected: all tests pass and analysis reports no issues.

- [ ] **Step 2: Update project summary**

Record the three-second CONNECT-based check, exhaustive node screening, and native restart/shutdown proxy recovery.

- [ ] **Step 3: Commit**

```bash
git add PROJECT_SUMMARY.md
git commit -m "docs: record connectivity and shutdown behavior"
```

## Self-review

- Spec coverage: Task 1 removes geo-IP/body work; Task 2 covers all nodes, three seconds, concurrency, and Stop; Task 3 covers restart/shutdown recovery and preservation of another disabled proxy value; Task 4 verifies and documents all changes.
- Placeholder scan: no unfinished implementation markers are present.
- Type consistency: Task 1 defines the helper used only by `node_health.dart`; Task 2 retains existing screening callbacks; Task 3 confines native restoration to the existing runner helper.
