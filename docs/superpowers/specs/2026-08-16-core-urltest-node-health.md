# Core URLTest Node Health Specification

## Goal

Make node availability mean that sing-box successfully sends a real request through that node and receives HTTP 204. A reachable TCP port must never be reported as a usable VPN node.

## Problem

Mobile currently calls `Socket.connect(node.server, node.port)`. With an active tunnel that connection can itself traverse the selected VPN node, so unrelated candidates become false green. A TCP handshake also does not validate protocol credentials, TLS, transport, or internet access.

## Required behavior

- Windows, Android, and iOS require HTTP 204 from `http://www.gstatic.com/generate_204` through the candidate sing-box outbound.
- Each candidate has a maximum three-second budget.
- Mobile checks execute through the live native sing-box core's Clash API after the VPN core has started; no TCP-only fallback.
- The selected connection remains usable while background checks run. The live core loads every node and routes normal traffic through a `selector` group; health checks call core URLTest for the individual candidate outbound.
- A successful subscription response that parses to zero nodes is explicit failure, never silent success.
- Shared Dart parsing yields the same result on all platforms; Windows diagnostics record status, content type, body length, and parsed count.
