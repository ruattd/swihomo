import Foundation

actor MihomoControllerClient {
    private let tunnel: TunnelController

    init(tunnel: TunnelController) {
        self.tunnel = tunnel
    }

    func proxyGroups(using overrides: ProxyOverrides) async throws -> [MihomoProxyGroup] {
        let response: MihomoProxyResponse = try await request(
            path: "proxies",
            method: "GET",
            overrides: overrides
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
        using overrides: ProxyOverrides
    ) async throws {
        struct Selection: Encodable { let name: String }
        let body = try JSONEncoder().encode(Selection(name: node))
        let _: EmptyResponse = try await request(
            path: "proxies/\(group)",
            method: "PUT",
            overrides: overrides,
            body: body
        )
    }

    func delay(
        for proxy: String,
        using overrides: ProxyOverrides,
        testURL: URL = URL(string: "https://www.gstatic.com/generate_204")!
    ) async throws -> Int? {
        let response: MihomoDelayResponse = try await request(
            path: "proxies/\(proxy)/delay",
            method: "GET",
            overrides: overrides,
            queryItems: [
                URLQueryItem(name: "url", value: testURL.absoluteString),
                URLQueryItem(name: "timeout", value: "5000")
            ]
        )
        return response.delay
    }

    func delays(
        in group: MihomoProxyGroup,
        using overrides: ProxyOverrides,
        testURL: URL = URL(string: "https://www.gstatic.com/generate_204")!
    ) async throws -> [String: Int] {
        try await request(
            path: "group/\(group.name)/delay",
            method: "GET",
            overrides: overrides,
            queryItems: [
                URLQueryItem(name: "url", value: testURL.absoluteString),
                URLQueryItem(name: "timeout", value: "5000")
            ]
        )
    }

    func updateExternalResource(
        _ resource: ExternalResource,
        using overrides: ProxyOverrides
    ) async throws {
        let providerType = switch resource.kind {
        case .proxyProvider: "proxies"
        case .ruleProvider: "rules"
        }
        let _: EmptyResponse = try await request(
            path: "providers/\(providerType)/\(resource.name)",
            method: "PUT",
            overrides: overrides
        )
    }

    func updateLogLevel(_ level: MihomoLogLevel, using overrides: ProxyOverrides) async throws {
        struct Configuration: Encodable {
            let logLevel: MihomoLogLevel

            enum CodingKeys: String, CodingKey {
                case logLevel = "log-level"
            }
        }

        let body = try JSONEncoder().encode(Configuration(logLevel: level))
        let _: EmptyResponse = try await request(
            path: "configs",
            method: "PATCH",
            overrides: overrides,
            body: body
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        overrides: ProxyOverrides,
        body: Data? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let message = MihomoControllerRequest(
            path: path,
            method: method,
            controllerPort: overrides.controllerPort,
            controllerSecret: overrides.controllerSecret,
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
}

private struct EmptyResponse: Decodable {}
