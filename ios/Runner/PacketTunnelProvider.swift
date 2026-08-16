import Foundation
import Libbox
import NetworkExtension

enum VpnError: LocalizedError {
    case configError(String)
    case libboxError(String)

    var errorDescription: String? {
        switch self {
        case .configError(let message): return "Configuration error: \(message)"
        case .libboxError(let message): return "libbox error: \(message)"
        }
    }
}

@available(iOS 15.0, *)
final class PacketTunnelProvider: NEPacketTunnelProvider, LibboxCommandServerHandlerProtocol {
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = LibboxPlatformInterface(provider: self)
    private var logLines = [String]()
    private var routingDiagnostics = [String]()
    private var configurationSummary = [String: Any]()
    private let logLock = NSLock()

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        let config = try tunnelConfiguration(options: options)
        logConfigurationSummary(config)
        appendLog("[packet-tunnel] configuring libbox")
        appendLog("[packet-tunnel] normal DNS routes through proxy")
        appendLog("[packet-tunnel] port 53 routes to the DNS outbound")

        try setupLibbox()
        guard let server = LibboxCommandServer(self, platformInterface: platformInterface) else {
            closeRuntime()
            throw VpnError.libboxError("create command server returned no instance")
        }

        do {
            // Do not call server.start(): that only opens libbox's optional
            // command socket, which is unnecessary and restricted in a
            // Network Extension sandbox. The in-process service API remains
            // available through startOrReloadService.
            try server.startOrReloadService(config, options: LibboxOverrideOptions())
        } catch {
            closeRuntime()
            throw VpnError.libboxError("start service: \(error.localizedDescription)")
        }

        commandServer = server
        appendLog("[packet-tunnel] libbox service started")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        appendLog("[packet-tunnel] stopping: \(reason.rawValue)")
        closeRuntime()
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let request = String(data: messageData, encoding: .utf8) else {
            return response(["error": "invalid request"])
        }
        switch request {
        case "ping":
            return Data("pong".utf8)
        case "status":
            return response([
                "running": commandServer != nil,
                "connected": commandServer != nil,
            ])
        case "diagnose":
            return response([
                "running": commandServer != nil,
                "platform": "ios",
                "engine": "libbox",
                "configSummary": configurationSummary,
            ])
        case "logs":
            return response([
                "lines": recentLogs(),
                "routingDiagnostics": recentRoutingDiagnostics(),
            ])
        case let request where request.hasPrefix("health:"):
            let fields = request.split(separator: ":", maxSplits: 2).map(String.init)
            guard fields.count == 3, let timeoutMs = Int(fields[2]) else {
                return response(["ok": false, "target": "HTTP 204", "error": "invalid health request"])
            }
            return await healthResponse(outboundTag: fields[1], timeoutMs: timeoutMs)
        case let request where request.hasPrefix("select:"):
            let outboundTag = String(request.dropFirst("select:".count))
            return await selectResponse(outboundTag: outboundTag)
        default:
            return response(["error": "unknown request"])
        }
    }

    func appendLog(_ line: String) {
        logLock.lock()
        logLines.append(line)
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        if line.hasPrefix("[diagnostic] routing") || line.hasPrefix("[diagnostic] expectation") {
            routingDiagnostics.append(line)
            if routingDiagnostics.count > 40 {
                routingDiagnostics.removeFirst(routingDiagnostics.count - 40)
            }
        }
        logLock.unlock()
    }

    func reloadService() async throws {
        guard let savedConfig = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["config"] as? String,
            !savedConfig.isEmpty else {
            throw VpnError.configError("Missing saved sing-box configuration")
        }
        guard let commandServer else {
            throw VpnError.libboxError("libbox command server is unavailable")
        }
        try commandServer.startOrReloadService(
            proxyDNSConfiguration(savedConfig),
            options: LibboxOverrideOptions()
        )
        appendLog("[packet-tunnel] service reloaded")
    }

    func postServiceClose() {
        commandServer = nil
    }

    func serviceReload() throws {
        Task { try? await self.reloadService() }
    }

    func serviceStop() throws {
        closeRuntime()
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_: Bool) throws {}

    func writeDebugMessage(_ message: String?) {
        if let message, !message.isEmpty { appendLog(message) }
    }

    private func tunnelConfiguration(options: [String: NSObject]?) throws -> String {
        if let config = options?["config"] as? String, !config.isEmpty {
            return proxyDNSConfiguration(config)
        }
        if let config = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["config"] as? String,
            !config.isEmpty {
            return proxyDNSConfiguration(config)
        }
        throw VpnError.configError("No sing-box configuration provided")
    }

    /// Preserve the shared DNS mode on iOS. Global mode uses the stable local
    /// resolver while smart routing uses remote DNS; all external connections
    /// still follow the proxy final route.
    private func proxyDNSConfiguration(_ configuration: String) -> String {
        guard let input = configuration.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: input),
              var root = object as? [String: Any],
              var dns = root["dns"] as? [String: Any] else {
            return configuration
        }

        let configuredDNSFinal = dns["final"] as? String ?? "local"
        root["dns"] = dns
        appendDNSRoutingDiagnostics(dns: dns, root: root, phase: "before-rewrite")

        // Only remote DNS needs the Cloudflare address removed from the
        // direct-rule list. Global mode intentionally keeps the stable local
        // resolver; external connections still use the proxy final route.
        if var route = root["route"] as? [String: Any],
           var rules = route["rules"] as? [Any] {
            // sing-box v1.13 removed the legacy `dns` outbound. Hijacking DNS
            // sends port-53 traffic to the configured DNS router instead.
            let hasDNSHijackRule = rules.contains { rule in
                let dictionary = rule as? [String: Any]
                return dictionary?["action"] as? String == "hijack-dns"
                    && (dictionary?["port"] as? [Int])?.contains(53) == true
            }
            if !hasDNSHijackRule {
                rules.insert(["action": "hijack-dns", "port": [53]], at: 0)
            }

            // The virtual resolver is 172.19.0.2:53. It is private, so the
            // generic private-address direct rule would otherwise match first.
            for index in rules.indices {
                guard var rule = rules[index] as? [String: Any],
                      rule["outbound"] as? String == "direct",
                      let cidrs = rule["ip_cidr"] as? [String] else {
                    continue
                }
                if configuredDNSFinal == "remote" || configuredDNSFinal.hasPrefix("remote-") {
                    rule["ip_cidr"] = cidrs.filter { $0 != "1.1.1.1/32" }
                }
                rules[index] = rule
            }
            route["rules"] = rules
            root["route"] = route
        }

        appendDNSRoutingDiagnostics(dns: root["dns"] as? [String: Any] ?? dns,
                                    root: root,
                                    phase: "after-rewrite")

        guard let output = try? JSONSerialization.data(withJSONObject: root),
              let rewritten = String(data: output, encoding: .utf8) else {
            return configuration
        }
        return rewritten
    }

    /// Log only routing metadata needed to diagnose DNS pollution or a
    /// mistaken direct match. Domain names are fixed public test domains;
    /// credentials and subscription content are never included.
    private func appendDNSRoutingDiagnostics(dns: [String: Any],
                                             root: [String: Any],
                                             phase: String) {
        let dnsFinal = dns["final"] as? String ?? "<missing>"
        let dnsRules = (dns["rules"] as? [[String: Any]] ?? []).enumerated().map {
            index, rule in
            let domains = (rule["domain_suffix"] as? [String] ?? []).joined(separator: "|")
            let exact = (rule["domain"] as? [String] ?? []).joined(separator: "|")
            let ruleSet = (rule["rule_set"] as? [String] ?? []).joined(separator: "|")
            let server = rule["server"] as? String ?? "<none>"
            let match = [exact, domains, ruleSet].filter { !$0.isEmpty }.joined(separator: ";")
            let description = match.isEmpty ? "any" : match
            return "\(index):\(description)=>\(server)"
        }.joined(separator: ",")

        let route = root["route"] as? [String: Any] ?? [:]
        let routeFinal = route["final"] as? String ?? "<missing>"
        let routeRules = (route["rules"] as? [[String: Any]] ?? []).enumerated().map {
            index, rule in
            let domains = (rule["domain_suffix"] as? [String] ?? []).joined(separator: "|")
            let exact = (rule["domain"] as? [String] ?? []).joined(separator: "|")
            let ruleSet = (rule["rule_set"] as? [String] ?? []).joined(separator: "|")
            let action = rule["action"] as? String
            let outbound = rule["outbound"] as? String
            let target = action ?? outbound ?? "<none>"
            let match = [exact, domains, ruleSet].filter { !$0.isEmpty }.joined(separator: ";")
            let description = match.isEmpty ? "any" : match
            return "\(index):\(description)=>\(target)"
        }.joined(separator: ",")

        appendLog("[diagnostic] routing phase=\(phase) dnsFinal=\(dnsFinal) "
            + "dnsRules=\(dnsRules)")
        appendLog("[diagnostic] routing phase=\(phase) routeFinal=\(routeFinal) "
            + "routeRules=\(routeRules)")
        appendLog("[diagnostic] routing expectation google.com/youtube.com "
            + "dns=\(dnsFinal) route=\(routeFinal)")
    }

    /// Emit a redacted configuration summary so an iOS device log can tell
    /// whether the AnyTLS node and DNS chain reached the packet tunnel.
    /// Password contents are deliberately never written to the log.
    private func logConfigurationSummary(_ configuration: String) {
        guard let input = configuration.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: input),
              let root = object as? [String: Any] else {
            configurationSummary = ["error": "config JSON could not be decoded"]
            appendLog("[diagnostic] config JSON could not be decoded")
            return
        }

        let outbounds = root["outbounds"] as? [[String: Any]] ?? []
        var summary = [String: Any]()
        if let anytls = outbounds.first(where: {
            ($0["type"] as? String)?.lowercased() == "anytls"
        }) {
            let server = anytls["server"] as? String ?? "<missing>"
            let port = anytls["server_port"] as? Int ?? 0
            let password = anytls["password"] as? String ?? ""
            let tls = anytls["tls"] as? [String: Any] ?? [:]
            let serverName = tls["server_name"] as? String ?? "<missing>"
            let insecure = tls["insecure"] as? Bool ?? false
            summary["anytls"] = true
            summary["server"] = server
            summary["port"] = port
            summary["sni"] = serverName
            summary["insecure"] = insecure
            summary["passwordLength"] = password.count
            appendLog("[diagnostic] anytls server=\(server) port=\(port) "
                + "sni=\(serverName) insecure=\(insecure) "
                + "passwordLength=\(password.count)")
        } else {
            let types = outbounds.compactMap { $0["type"] as? String }.joined(separator: ",")
            summary["anytls"] = false
            summary["outbounds"] = types
            appendLog("[diagnostic] anytls outbound missing; outbounds=\(types)")
        }

        let dns = root["dns"] as? [String: Any] ?? [:]
        let dnsFinal = dns["final"] as? String ?? "<missing>"
        let dnsServers = (dns["servers"] as? [[String: Any]] ?? []).compactMap { server in
            let tag = server["tag"] as? String ?? "?"
            let type = server["type"] as? String ?? "?"
            let detour = server["detour"] as? String ?? "direct"
            return "\(tag):\(type):\(detour)"
        }.joined(separator: ",")
        summary["dnsFinal"] = dnsFinal
        summary["dnsServers"] = dnsServers
        appendLog("[diagnostic] dns final=\(dnsFinal) servers=\(dnsServers)")

        let route = root["route"] as? [String: Any] ?? [:]
        let routeFinal = route["final"] as? String ?? "<missing>"
        let routeRuleList = route["rules"] as? [[String: Any]] ?? []
        let routeRules = routeRuleList.count
        let directRuleSummary = routeRuleList.enumerated().compactMap { index, rule -> String? in
            guard rule["outbound"] as? String == "direct" else { return nil }
            let domains = (rule["domain"] as? [String] ?? []).joined(separator: "|")
            let cidrs = (rule["ip_cidr"] as? [String] ?? []).joined(separator: "|")
            let ruleSet = (rule["rule_set"] as? [String] ?? []).joined(separator: "|")
            let match = [domains, cidrs, ruleSet].filter { !$0.isEmpty }.joined(separator: ";")
            return "\(index):\(match.isEmpty ? "any" : match)"
        }.joined(separator: ",")
        summary["routeFinal"] = routeFinal
        summary["routeRules"] = routeRules
        summary["directRuleSummary"] = directRuleSummary
        configurationSummary = summary
        appendLog("[diagnostic] route final=\(routeFinal) rules=\(routeRules)")
        appendLog("[diagnostic] direct rules=\(directRuleSummary.isEmpty ? "none" : directRuleSummary)")
    }

    private func closeRuntime() {
        if let commandServer {
            try? commandServer.closeService()
            commandServer.close()
        }
        commandServer = nil
        platformInterface.reset()
    }

    /// The Clash API asks the running sing-box core to URL-test the named
    /// outbound. It is intentionally run inside the Packet Tunnel process so
    /// the app process never tests a candidate through the currently selected
    /// VPN route.
    private func healthResponse(outboundTag: String, timeoutMs: Int) async -> Data? {
        guard commandServer != nil else {
            return response([
                "ok": false,
                "target": "HTTP 204",
                "error": "VPN core is not running",
            ])
        }
        guard let encodedTag = outboundTag.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            return response(["ok": false, "target": "HTTP 204", "error": "invalid outbound tag"])
        }
        var components = URLComponents(
            string: "http://127.0.0.1:9090/proxies/\(encodedTag)/delay"
        )!
        components.queryItems = [
            URLQueryItem(name: "url", value: "http://www.gstatic.com/generate_204"),
            URLQueryItem(name: "timeout", value: String(max(1, timeoutMs))),
        ]
        guard let url = components.url else {
            return response(["ok": false, "target": "HTTP 204", "error": "invalid health URL"])
        }

        let startedAt = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(max(1, timeoutMs)) / 1000.0
        do {
            let (data, rawResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = rawResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delay = json["delay"] as? NSNumber,
                  delay.intValue >= 0 else {
                return response(["ok": false, "target": "HTTP 204", "error": "core URLTest failed"])
            }
            let latency = max(1, delay.intValue)
            appendLog("[health] outbound=\(outboundTag) HTTP 204 latency=\(latency)ms")
            return response(["ok": true, "target": "HTTP 204", "latency": latency])
        } catch {
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            appendLog("[health] outbound=\(outboundTag) failed after \(elapsed)ms: \(error.localizedDescription)")
            return response([
                "ok": false,
                "target": "HTTP 204",
                "error": error.localizedDescription,
            ])
        }
    }

    private func selectResponse(outboundTag: String) async -> Data? {
        guard commandServer != nil else {
            return response(["ok": false, "error": "VPN core is not running"])
        }
        guard !outboundTag.isEmpty,
              let url = URL(string: "http://127.0.0.1:9090/proxies/proxy") else {
            return response(["ok": false, "error": "invalid outbound tag"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": outboundTag])
        do {
            let (_, rawResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = rawResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
                return response(["ok": false, "error": "selector API failed"])
            }
            appendLog("[selector] selected outbound=\(outboundTag)")
            return response(["ok": true])
        } catch {
            return response(["ok": false, "error": error.localizedDescription])
        }
    }

    private func setupLibbox() throws {
        let basePath = FileManager.default.temporaryDirectory.path
        let options = LibboxSetupOptions()
        options.basePath = basePath
        options.workingPath = basePath
        options.tempPath = basePath
        options.fixAndroidStack = false
        options.logMaxLines = 3000
        options.debug = true
        var setupError: NSError?
        guard LibboxSetup(options, &setupError) else {
            throw setupError ?? VpnError.libboxError("libbox setup failed")
        }
    }

    private func recentLogs() -> [String] {
        logLock.lock()
        defer { logLock.unlock() }
        return logLines
    }

    private func recentRoutingDiagnostics() -> [String] {
        logLock.lock()
        defer { logLock.unlock() }
        return routingDiagnostics
    }

    private func response(_ value: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: value)
    }
}
