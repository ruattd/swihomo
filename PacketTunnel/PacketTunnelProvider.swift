import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var core: (any MihomoCoreEngine)?

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let configuration = protocolConfiguration as? NETunnelProviderProtocol,
              let rawProfileID = configuration.providerConfiguration?["profileID"] as? String,
              UUID(uuidString: rawProfileID) != nil else {
            throw ClientError.missingProfile
        }

        guard let profileYAML = configuration.providerConfiguration?["profileYAML"] as? Data,
              let overridesYAML = configuration.providerConfiguration?["overridesYAML"] as? Data else {
            throw ClientError.missingProfile
        }
        let dnsEnabled = (configuration.providerConfiguration?["dnsEnabled"] as? NSNumber)?.boolValue ?? true

        try await setTunnelNetworkSettings(networkSettings(dnsEnabled: dnsEnabled))

        let core = MihomoCoreFactory.make()
        try await core.start(
            configuration: MihomoRuntimeConfiguration(
                profileYAML: profileYAML,
                overridesYAML: overridesYAML
            ),
            packetFlow: packetFlow
        )
        self.core = core
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Task {
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

    private func networkSettings(dnsEnabled: Bool) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(
            addresses: ["fd00::1"],
            networkPrefixLengths: [NSNumber(value: 64)]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        settings.mtu = 1500

        if dnsEnabled {
            // The default route sends these resolver queries through mihomo's packet flow.
            settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "2606:4700:4700::1111"])
        }
        return settings
    }
}
