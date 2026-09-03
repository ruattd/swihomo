import Foundation

actor MihomoControllerClient {
    private let tunnel: TunnelController

    init(tunnel: TunnelController) {
        self.tunnel = tunnel
    }

    func proxyGroups() async throws -> [MihomoProxyGroup] {
        let response: MihomoProxyResponse = try await request(
            path: "proxies",
            method: "GET",
        )

        return response.proxies
            .filter { !$0.all.isEmpty }
            .map { proxy in
                MihomoProxyGroup(
                    name: proxy.name,
                    selected: proxy.now,
                    candidates: proxy.all
                )
            }
    }

    func select(
        node: String,
        in group: String,
    ) async throws {
        struct Selection: Encodable { let name: String }
        let body = try JSONEncoder().encode(Selection(name: node))
        let _: EmptyResponse = try await request(
            path: "proxies/\(group)",
            method: "PUT",
            body: body
        )
    }

    func delay(
        for proxy: String,
        testURL: URL = URL(string: "https://www.gstatic.com/generate_204")!
    ) async throws -> Int? {
        do {
            let response: MihomoDelayResponse = try await request(
                path: "proxies/\(proxy)/delay",
                method: "GET",
                queryItems: delayQueryItems(testURL: testURL)
            )
            return response.delay
        } catch ClientError.httpFailure(let code) where code == 404 {
            // Provider-backed nodes are absent from mihomo's global proxy map, so the generic
            // endpoint 404s; test them through their owning provider's healthcheck instead.
            return try await providerNodeDelay(for: proxy, testURL: testURL)
        }
    }

    private func providerNodeDelay(
        for proxy: String,
        testURL: URL
    ) async throws -> Int? {
        let providers: MihomoProviderResponse = try await request(
            path: "providers/proxies",
            method: "GET",
        )
        guard let providerName = providers.providers.first(where: {
            $0.value.proxies?.contains { $0.name == proxy } == true
        })?.key else {
            throw ClientError.httpFailure(404)
        }
        let response: MihomoDelayResponse = try await request(
            path: "providers/proxies/\(providerName)/\(proxy)/healthcheck",
            method: "GET",
            queryItems: delayQueryItems(testURL: testURL)
        )
        return response.delay
    }

    /// One-shot whole-group test: mihomo returns only the nodes that answered, so
    /// absent candidates are the failures — timeout and test error are not distinguished.
    func groupDelay(
        for group: String,
        testURL: URL = URL(string: "https://www.gstatic.com/generate_204")!
    ) async throws -> [String: Int] {
        try await request(
            path: "group/\(group)/delay",
            method: "GET",
            queryItems: delayQueryItems(testURL: testURL)
        )
    }

    private func delayQueryItems(testURL: URL) -> [URLQueryItem] {
        [
            URLQueryItem(name: "url", value: testURL.absoluteString),
            URLQueryItem(name: "timeout", value: "5000")
        ]
    }

    func connections() async throws -> [MihomoConnection] {
        let response: MihomoConnectionResponse = try await request(
            path: "connections",
            method: "GET",
        )
        return response.connections
    }

    func closeConnection(id: String) async throws {
        let _: EmptyResponse = try await request(
            path: "connections/\(id)",
            method: "DELETE",
        )
    }

    func closeAllConnections() async throws {
        let _: EmptyResponse = try await request(
            path: "connections",
            method: "DELETE",
        )
    }

    func updateExternalResource(
        _ resource: ExternalResource,
    ) async throws {
        let providerType = switch resource.kind {
        case .proxyProvider: "proxies"
        case .ruleProvider: "rules"
        case .geoData:
            throw ClientError.controllerRequestFailed("Geo databases are loaded when the Packet Tunnel reconnects.")
        }
        let _: EmptyResponse = try await request(
            path: "providers/\(providerType)/\(resource.name)",
            method: "PUT",
        )
    }

    func updateGeoData() async throws {
        let _: EmptyResponse = try await request(
            path: "upgrade/geo",
            method: "POST",
        )
    }

    func externalResourceDetails() async throws -> [String: MihomoProviderDetails] {
        async let proxyProviderDetailsTask = providerDetails(
            path: "providers/proxies",
            kind: .proxyProvider,
        )
        async let ruleProviderDetailsTask = providerDetails(
            path: "providers/rules",
            kind: .ruleProvider,
        )
        let (proxyProviderDetails, ruleProviderDetails) = try await (proxyProviderDetailsTask, ruleProviderDetailsTask)
        return proxyProviderDetails.merging(ruleProviderDetails) { _, latest in latest }
    }

    /// Hot-updates the basic settings mihomo supports on PATCH /configs. Nil fields are
    /// omitted from the payload, so callers pass only what changed. dns and the external
    /// controller have no patch path — those still require a reconnect.
    func updateGeneral(
        mode: ProxyMode? = nil,
        logLevel: MihomoLogLevel? = nil,
        mixedPort: Int? = nil,
        allowLAN: Bool? = nil,
        ipv6Enabled: Bool? = nil
    ) async throws {
        struct Configuration: Encodable {
            var mode: ProxyMode?
            var logLevel: MihomoLogLevel?
            var mixedPort: Int?
            var allowLAN: Bool?
            var ipv6: Bool?

            enum CodingKeys: String, CodingKey {
                case mode
                case logLevel = "log-level"
                case mixedPort = "mixed-port"
                case allowLAN = "allow-lan"
                case ipv6
            }
        }

        let body = try JSONEncoder().encode(Configuration(
            mode: mode,
            logLevel: logLevel,
            mixedPort: mixedPort,
            allowLAN: allowLAN,
            ipv6: ipv6Enabled
        ))
        let _: EmptyResponse = try await request(
            path: "configs",
            method: "PATCH",
            body: body
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let message = MihomoControllerRequest(
            path: path,
            method: method,
            body: body,
            queryItems: queryItems.map {
                MihomoControllerQueryItem(name: $0.name, value: $0.value)
            }
        )
        let response = try await tunnel.controllerResponse(for: message)

        if let errorMessage = response.errorMessage {
            throw ClientError.controllerRequestFailed(errorMessage)
        }
        guard let statusCode = response.statusCode else {
            throw ClientError.controllerRequestFailed("The Packet Tunnel did not return a controller response.")
        }
        guard (200..<300).contains(statusCode) else {
            throw ClientError.httpFailure(statusCode)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: response.body)
    }

    private func providerDetails(
        path: String,
        kind: ExternalResourceKind,
    ) async throws -> [String: MihomoProviderDetails] {
        let response: MihomoProviderResponse = try await request(
            path: path,
            method: "GET",
        )
        return response.providers.reduce(into: [:]) { details, provider in
            details["\(kind.rawValue):\(provider.key)"] = MihomoProviderDetails(
                updatedAt: date(from: provider.value.updatedAt),
                subscriptionInfo: kind == .proxyProvider ? provider.value.subscriptionInfo : nil,
                ruleCount: kind == .ruleProvider ? provider.value.ruleCount : nil,
                format: kind == .ruleProvider ? provider.value.format : nil
            )
        }
    }

    private func date(from value: String?) -> Date? {
        guard let value else { return nil }

        let fractionalSecondsFormatter = ISO8601DateFormatter()
        fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalSecondsFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date, date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
}

private struct EmptyResponse: Decodable {}
