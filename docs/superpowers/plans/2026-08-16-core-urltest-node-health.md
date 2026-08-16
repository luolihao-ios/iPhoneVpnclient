# Core URLTest Node Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mobile TCP node checks with native sing-box HTTP-204 checks and make zero-node Windows imports explicit.

**Architecture:** Mobile connection configuration loads every candidate as an individually tagged outbound plus a `proxy` selector group whose default is the selected node. Native iOS/Android code sends a local Clash API delay request for a requested outbound, so sing-box itself performs the HTTP-204 test. Dart retains scheduling and cancellation but uses the native core checker on mobile after it is running.

**Tech Stack:** Flutter/Dart, sing-box JSON, Swift/Libbox, Kotlin/Libbox, MethodChannel.

## Global Constraints

- HTTP 204 from `http://www.gstatic.com/generate_204` is the only availability success condition.
- Individual checks time out after 3 seconds.
- No TCP-only mobile fallback.
- Parsing zero nodes must be visible to the user.

---

### Task 1: Isolated health configuration

**Files:**
- Modify: `lib/core/singbox_config.dart`
- Create: `test/node_health_config_test.dart`

- [ ] Write a failing test for `buildSingBoxHealthCheckConfig(node, httpPort)` that asserts a loopback HTTP inbound, candidate `health-proxy` final route, and no API/cache state.
- [ ] Run `flutter test test/node_health_config_test.dart` and confirm it fails because the builder does not exist.
- [ ] Implement the smallest test-only configuration builder using `_nodeToOutbound` and `health-proxy` tag.
- [ ] Re-run `flutter test test/node_health_config_test.dart` and confirm it passes.

### Task 2: Replace mobile TCP decision path

**Files:**
- Modify: `lib/providers/app_provider.dart`
- Modify: `lib/core/node_health.dart`
- Modify: `test/app_provider_screening_test.dart`

- [ ] Write a failing test injecting a `mobileHealthChecker`; assert mobile screening calls it and never calls `tcpChecker`.
- [ ] Run `flutter test test/app_provider_screening_test.dart` and confirm it fails due to the missing injection.
- [ ] Add `MobileNodeHealthChecker` and use it in mobile `pingNode`, initial screening, and manual full check paths.
- [ ] Re-run the targeted test and confirm it passes.

### Task 3: Native iOS and Android HTTP-204 bridge

**Files:**
- Modify: `ios/Runner/VpnPlugin.swift`
- Modify: `ios/Runner/PacketTunnelProvider.swift`
- Modify: `android/app/src/main/kotlin/com/example/forge_vpn_flutter/LibboxServiceController.kt`
- Modify: `android/app/src/main/kotlin/com/example/forge_vpn_flutter/VpnBridge.kt`
- Modify: `lib/services/ios_vpn_service.dart`
- Modify: `lib/services/android_vpn_service.dart`
- Create: `test/mobile_node_health_bridge_test.dart`

- [ ] Write a failing MethodChannel mapping test for a native `{ok, latency, target, error}` result.
- [ ] Run `flutter test test/mobile_node_health_bridge_test.dart` and confirm it fails because no bridge method exists.
- [ ] Add `checkNodeHealth(outboundTag, timeoutMs)` that forwards a local Clash API delay request to the active native core. It must require an active core and never use Flutter TCP reachability.
- [ ] Run `flutter test test/mobile_node_health_bridge_test.dart test/ios_vpn_plugin_source_test.dart` and confirm it passes.

### Task 4: Explicit zero-node import outcome

**Files:**
- Modify: `lib/core/subscription.dart`
- Modify: `lib/providers/app_provider.dart`
- Modify: `test/subscription_tolerance_test.dart`

- [ ] Write a failing test for a successful response containing zero supported nodes.
- [ ] Run the targeted test and confirm the import currently succeeds silently.
- [ ] Preserve the old subscription and return `订阅内容中没有可识别的节点` for this result.
- [ ] Re-run the targeted test and confirm it passes.

### Task 5: Verification and documentation

**Files:**
- Modify: `PROJECT_SUMMARY.md`

- [ ] Run `flutter test`.
- [ ] Run `flutter analyze`.
- [ ] Document the HTTP-204 definition and zero-node import result.
