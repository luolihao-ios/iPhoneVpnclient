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
            return response(["lines": recentLogs()])
        default:
            return response(["error": "unknown request"])
        }
    }

    func appendLog(_ line: String) {
        logLock.lock()
        logLines.append(line)
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
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
                if configuredDNSFinal == "remote" {
                    rule["ip_cidr"] = cidrs.filter { $0 != "1.1.1.1/32" }
                }
                rules[index] = rule
            }
            route["rules"] = rules
            root["route"] = route
        }

        guard let output = try? JSONSerialization.data(withJSONObject: root),
              let rewritten = String(data: output, encoding: .utf8) else {
            return configuration
        }
        return rewritten
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

    private func response(_ value: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: value)
    }
}
