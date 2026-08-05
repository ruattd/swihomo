import Foundation
import NetworkExtension
import Network

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var core: (any MihomoCoreEngine)?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let memoryPressureQueue = DispatchQueue(label: "com.swihomo.memory-pressure")

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let configuration = protocolConfiguration as? NETunnelProviderProtocol,
              let rawProfileID = configuration.providerConfiguration?["profileID"] as? String,
              UUID(uuidString: rawProfileID) != nil else {
            throw ClientError.missingProfile
        }

        guard let profileYAML = configuration.providerConfiguration?["profileYAML"] as? Data else {
            throw ClientError.missingProfile
        }
        let dnsEnabled = (configuration.providerConfiguration?["dnsEnabled"] as? NSNumber)?.boolValue ?? true
        let automaticallyReclaimsMemory = (configuration.providerConfiguration?["automaticallyReclaimsMemory"] as? NSNumber)?.boolValue ?? false
        let bypassedCIDRs = configuration.providerConfiguration?["bypassedCIDRs"] as? [String] ?? []
        let mtu = (configuration.providerConfiguration?["mtu"] as? NSNumber)?.intValue ?? PacketTunnelMTULimits.defaultValue
        let customDNSServers = configuration.providerConfiguration?["customDNSServers"] as? [String] ?? []
        let ipv6Enabled = (configuration.providerConfiguration?["ipv6Enabled"] as? NSNumber)?.boolValue ?? true

        // Download required geodata before the default route reaches the core's packet flow.
        let geoDataRequirements = MihomoGeoDataRequirements(profileYAML: profileYAML)
        try await MihomoCoreFactory.prewarmGeoData(requiring: geoDataRequirements)
        try await setTunnelNetworkSettings(
            networkSettings(
                dnsEnabled: dnsEnabled,
                bypassedCIDRs: bypassedCIDRs,
                mtu: mtu,
                customDNSServers: customDNSServers,
                ipv6Enabled: ipv6Enabled
            )
        )

        let core = MihomoCoreFactory.make()
        do {
            try await core.start(
                configuration: MihomoRuntimeConfiguration(profileYAML: profileYAML),
                packetFlow: packetFlow
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let tunnelError = NSError(
                domain: "com.swihomo.mihomo",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: message,
                    NSLocalizedFailureReasonErrorKey: message,
                    NSUnderlyingErrorKey: error as NSError
                ]
            )
            CoreLogStore.append(level: .error, message: "Failed to start Mihomo core: \(message)")
            cancelTunnelWithError(tunnelError)
            throw tunnelError
        }
        self.core = core
        if automaticallyReclaimsMemory {
            startMemoryPressureMonitoring()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Task {
            stopMemoryPressureMonitoring()
            await core?.stop()
            core = nil
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            let response = await handleProviderMessage(messageData)
            completionHandler?(try? JSONEncoder().encode(response))
        }
    }

    private func handleProviderMessage(_ messageData: Data) async -> TunnelProviderResponse {
        do {
            let request = try JSONDecoder().decode(TunnelProviderRequest.self, from: messageData)
            switch request.operation {
            case .controller:
                guard let controllerRequest = request.controllerRequest else {
                    throw ClientError.controllerRequestFailed("The controller request is missing.")
                }
                return TunnelProviderResponse(
                    controllerResponse: await handleControllerRequest(controllerRequest),
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .coreLogs:
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: CoreLogStore.entries(),
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .clearCoreLogs:
                CoreLogStore.clear()
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .proxyGroupOrder:
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: nil,
                    proxyGroupOrder: try MihomoCoreProxyGroups.order(),
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .externalResources:
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: try MihomoCoreResources.list(),
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .readExternalResource:
                guard let identifier = request.resourceIdentifier else {
                    throw ClientError.controllerRequestFailed("The external resource identifier is missing.")
                }
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: try MihomoCoreResources.read(identifier: identifier),
                    errorMessage: nil
                )
            case .writeExternalResource:
                guard let identifier = request.resourceIdentifier,
                      let contents = request.resourceContents else {
                    throw ClientError.controllerRequestFailed("The external resource contents are missing.")
                }
                try MihomoCoreResources.write(identifier: identifier, contents: contents)
                return TunnelProviderResponse(
                    controllerResponse: nil,
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            }
        } catch {
            return TunnelProviderResponse(
                controllerResponse: nil,
                coreLogs: nil,
                proxyGroupOrder: nil,
                externalResources: nil,
                resourceContents: nil,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func handleControllerRequest(_ request: MihomoControllerRequest) async -> MihomoControllerResponse {
        do {
            let (data, statusCode) = try await performControllerRequest(request)
            return MihomoControllerResponse(statusCode: statusCode, body: data, errorMessage: nil)
        } catch {
            return MihomoControllerResponse(
                statusCode: nil,
                body: Data(),
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func performControllerRequest(_ request: MihomoControllerRequest) async throws -> (Data, Int) {
        guard (1...65535).contains(request.controllerPort) else {
            throw URLError(.badURL)
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = request.controllerPort
        components.path = "/\(request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        components.queryItems = request.queryItems.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !request.controllerSecret.isEmpty {
            urlRequest.setValue("Bearer \(request.controllerSecret)", forHTTPHeaderField: "Authorization")
        }

        let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response.statusCode)
    }

    private func networkSettings(
        dnsEnabled: Bool,
        bypassedCIDRs: [String],
        mtu: Int,
        customDNSServers: [String],
        ipv6Enabled: Bool
    ) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let excludedRoutes = excludedRoutes(
            from: bypassedCIDRs
        )
        ipv4.excludedRoutes = excludedRoutes.ipv4
        if ipv6Enabled {
            let ipv6 = NEIPv6Settings(
                addresses: ["fd00::1"],
                networkPrefixLengths: [NSNumber(value: 64)]
            )
            ipv6.includedRoutes = [NEIPv6Route.default()]
            ipv6.excludedRoutes = excludedRoutes.ipv6
            settings.ipv6Settings = ipv6
        }
        settings.mtu = NSNumber(value: min(max(mtu, PacketTunnelMTULimits.minimum), PacketTunnelMTULimits.maximum))

        let dnsServers = validDNSServers(from: customDNSServers, allowsIPv6: ipv6Enabled)
        if !dnsServers.isEmpty {
            settings.dnsSettings = NEDNSSettings(servers: dnsServers)
        } else if dnsEnabled {
            // The default route sends these resolver queries through mihomo's packet flow.
            settings.dnsSettings = NEDNSSettings(
                servers: ipv6Enabled ? ["1.1.1.1", "2606:4700:4700::1111"] : ["1.1.1.1"]
            )
        }
        return settings
    }

    private func validDNSServers(from servers: [String], allowsIPv6: Bool) -> [String] {
        var seenServers = Set<String>()
        return servers.filter { server in
            guard IPv4Address(server) != nil || (allowsIPv6 && IPv6Address(server) != nil) else {
                return false
            }
            return seenServers.insert(server).inserted
        }
    }

    private func excludedRoutes(
        from cidrs: [String]
    ) -> (ipv4: [NEIPv4Route], ipv6: [NEIPv6Route]) {
        var ipv4Routes: [NEIPv4Route] = []
        var ipv6Routes: [NEIPv6Route] = []
        var seenCIDRs = Set<String>()

        for cidr in cidrs {
            let components = cidr.split(separator: "/", maxSplits: 1)
            guard components.count == 2,
                  let prefixLength = Int(components[1]) else {
                continue
            }

            let address = String(components[0])
            let normalizedCIDR = "\(address)/\(prefixLength)"
            guard seenCIDRs.insert(normalizedCIDR).inserted else { continue }

            if IPv4Address(address) != nil, (0...32).contains(prefixLength) {
                let subnetMask = ipv4SubnetMask(prefixLength: prefixLength)
                ipv4Routes.append(NEIPv4Route(destinationAddress: address, subnetMask: subnetMask))
            } else if IPv6Address(address) != nil, (0...128).contains(prefixLength) {
                ipv6Routes.append(
                    NEIPv6Route(
                        destinationAddress: address,
                        networkPrefixLength: NSNumber(value: prefixLength)
                    )
                )
            }
        }

        return (ipv4Routes, ipv6Routes)
    }

    private func ipv4SubnetMask(prefixLength: Int) -> String {
        let mask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength)
        return [24, 16, 8, 0]
            .map { String((mask >> $0) & 0xFF) }
            .joined(separator: ".")
    }

    private func startMemoryPressureMonitoring() {
        stopMemoryPressureMonitoring()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: memoryPressureQueue)
        source.setEventHandler { [weak self] in
            guard let self, self.memoryPressureSource === source else { return }
            guard let usage = self.core?.reclaimMemory() else { return }
            CoreLogStore.append(
                level: .warning,
                message: "Critical memory pressure detected; mihomo heap memory: \(formatMemoryUsage(usage.before)) -> \(formatMemoryUsage(usage.after))."
            )
        }
        memoryPressureSource = source
        source.resume()
    }

    private func stopMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func formatMemoryUsage(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
