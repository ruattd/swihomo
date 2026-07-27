import Foundation

enum ProfileSource: String, Codable, CaseIterable, Identifiable {
    case local
    case remote

    var id: Self { self }

    var displayName: String {
        switch self {
        case .local: "Local"
        case .remote: "Online"
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var source: ProfileSource
    var remoteURL: URL?
    var customUserAgent: String?
    var createdAt: Date
    var updatedAt: Date
    var lastFetchedAt: Date?

    var detail: String {
        switch source {
        case .local:
            "Imported configuration"
        case .remote:
            remoteURL?.host ?? "Online configuration"
        }
    }
}

enum ProxyMode: String, Codable, CaseIterable, Identifiable {
    case rule
    case global
    case direct

    var id: Self { self }

    var displayName: String { rawValue.capitalized }
}

enum MihomoLogLevel: String, Codable, CaseIterable, Identifiable {
    case debug
    case info
    case warning
    case error
    case silent

    var id: Self { self }
    var displayName: String { rawValue.capitalized }
}

struct ProxyOverrides: Codable, Equatable {
    var mode: ProxyMode
    var logLevel: MihomoLogLevel
    var mixedPort: Int
    var allowLAN: Bool
    var ipv6Enabled: Bool
    var dnsEnabled: Bool
    var controllerPort: Int
    var controllerSecret: String
    var customYAML: String

    private enum CodingKeys: String, CodingKey {
        case mode
        case logLevel
        case mixedPort
        case allowLAN
        case ipv6Enabled
        case dnsEnabled
        case controllerPort
        case controllerSecret
        case customYAML
    }

    init(
        mode: ProxyMode,
        logLevel: MihomoLogLevel = .info,
        mixedPort: Int,
        allowLAN: Bool,
        ipv6Enabled: Bool,
        dnsEnabled: Bool,
        controllerPort: Int,
        controllerSecret: String,
        customYAML: String = ""
    ) {
        self.mode = mode
        self.logLevel = logLevel
        self.mixedPort = mixedPort
        self.allowLAN = allowLAN
        self.ipv6Enabled = ipv6Enabled
        self.dnsEnabled = dnsEnabled
        self.controllerPort = controllerPort
        self.controllerSecret = controllerSecret
        self.customYAML = customYAML
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ProxyMode.self, forKey: .mode)
        logLevel = try container.decodeIfPresent(MihomoLogLevel.self, forKey: .logLevel) ?? .info
        mixedPort = try container.decode(Int.self, forKey: .mixedPort)
        allowLAN = try container.decode(Bool.self, forKey: .allowLAN)
        ipv6Enabled = try container.decode(Bool.self, forKey: .ipv6Enabled)
        dnsEnabled = try container.decode(Bool.self, forKey: .dnsEnabled)
        controllerPort = try container.decode(Int.self, forKey: .controllerPort)
        controllerSecret = try container.decode(String.self, forKey: .controllerSecret)
        customYAML = try container.decodeIfPresent(String.self, forKey: .customYAML) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(mixedPort, forKey: .mixedPort)
        try container.encode(allowLAN, forKey: .allowLAN)
        try container.encode(ipv6Enabled, forKey: .ipv6Enabled)
        try container.encode(dnsEnabled, forKey: .dnsEnabled)
        try container.encode(controllerPort, forKey: .controllerPort)
        try container.encode(controllerSecret, forKey: .controllerSecret)
        try container.encode(customYAML, forKey: .customYAML)
    }

    static func `default`() -> ProxyOverrides {
        ProxyOverrides(
            mode: .rule,
            logLevel: .info,
            mixedPort: 7890,
            allowLAN: false,
            ipv6Enabled: false,
            dnsEnabled: true,
            controllerPort: 9090,
            controllerSecret: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            customYAML: ""
        )
    }
}

struct ClientSnapshot: Codable {
    var schemaVersion: Int
    var profiles: [Profile]
    var activeProfileID: UUID?
    var overrides: ProxyOverrides

    static func empty() -> ClientSnapshot {
        ClientSnapshot(
            schemaVersion: 1,
            profiles: [],
            activeProfileID: nil,
            overrides: .default()
        )
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }
}

struct MihomoProxy: Decodable, Identifiable, Hashable {
    let name: String
    let type: String
    let all: [String]
    let now: String?

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case all
        case now
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        all = try container.decodeIfPresent([String].self, forKey: .all) ?? []
        now = try container.decodeIfPresent(String.self, forKey: .now)
    }
}

struct MihomoProxyResponse: Decodable {
    let proxies: [MihomoProxy]

    private enum CodingKeys: String, CodingKey {
        case proxies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let proxiesContainer = try container.nestedContainer(
            keyedBy: MihomoProxyCodingKey.self,
            forKey: .proxies
        )
        proxies = try proxiesContainer.allKeys.map {
            try proxiesContainer.decode(MihomoProxy.self, forKey: $0)
        }
    }
}

private struct MihomoProxyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

struct MihomoProxyGroup: Identifiable, Hashable {
    let name: String
    let selected: String?
    let candidates: [String]

    var id: String { name }
}

enum ProxyGroupSortCriterion: String, CaseIterable, Identifiable {
    case original
    case name

    var id: Self { self }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .name: "Name"
        }
    }
}

enum ProxyNodeSortCriterion: String, CaseIterable, Identifiable {
    case original
    case name
    case delay

    var id: Self { self }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .name: "Name"
        case .delay: "Delay"
        }
    }
}

enum ConnectionSortCriterion: String, CaseIterable, Identifiable {
    case process
    case speed
    case rule

    var id: Self { self }

    var displayName: String {
        switch self {
        case .process: "Process"
        case .speed: "Live Speed"
        case .rule: "Rule"
        }
    }
}

enum ProxySortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}

struct MihomoDelayResponse: Decodable {
    let delay: Int?
}

struct MihomoConnectionResponse: Decodable {
    let connections: [MihomoConnection]
}

struct MihomoConnection: Decodable, Identifiable, Hashable {
    let id: String
    let metadata: MihomoConnectionMetadata
    let upload: Int64
    let download: Int64
    let startedAt: String?
    let chains: [String]
    let providerChains: [String]
    let rule: String
    let rulePayload: String

    private enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case upload
        case download
        case startedAt = "start"
        case chains
        case providerChains
        case rule
        case rulePayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        metadata = try container.decode(MihomoConnectionMetadata.self, forKey: .metadata)
        upload = try container.decodeIfPresent(Int64.self, forKey: .upload) ?? 0
        download = try container.decodeIfPresent(Int64.self, forKey: .download) ?? 0
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        chains = try container.decodeIfPresent([String].self, forKey: .chains) ?? []
        providerChains = try container.decodeIfPresent([String].self, forKey: .providerChains) ?? []
        rule = try container.decodeIfPresent(String.self, forKey: .rule) ?? ""
        rulePayload = try container.decodeIfPresent(String.self, forKey: .rulePayload) ?? ""
    }

    var processName: String {
        metadata.process.isEmpty ? "Unknown Process" : metadata.process
    }

    var destination: String {
        if !metadata.host.isEmpty { return metadata.host }
        if !metadata.remoteDestination.isEmpty { return metadata.remoteDestination }
        return metadata.destinationIP
    }

    var ruleDescription: String {
        [rule, rulePayload]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var routingDescription: String {
        let chain = chains.joined(separator: " > ")
        return [ruleDescription, chain]
            .filter { !$0.isEmpty }
            .joined(separator: " -> ")
    }
}

struct MihomoConnectionMetadata: Decodable, Hashable {
    let network: String
    let type: String
    let sourceIP: String
    let sourcePort: String
    let destinationIP: String
    let destinationPort: String
    let host: String
    let process: String
    let processPath: String
    let remoteDestination: String

    private enum CodingKeys: String, CodingKey {
        case network
        case type
        case sourceIP
        case sourcePort
        case destinationIP
        case destinationPort
        case host
        case process
        case processPath
        case remoteDestination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        sourceIP = try container.decodeIfPresent(String.self, forKey: .sourceIP) ?? ""
        sourcePort = try Self.stringValue(forKey: .sourcePort, in: container)
        destinationIP = try container.decodeIfPresent(String.self, forKey: .destinationIP) ?? ""
        destinationPort = try Self.stringValue(forKey: .destinationPort, in: container)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        process = try container.decodeIfPresent(String.self, forKey: .process) ?? ""
        processPath = try container.decodeIfPresent(String.self, forKey: .processPath) ?? ""
        remoteDestination = try container.decodeIfPresent(String.self, forKey: .remoteDestination) ?? ""
    }

    private static func stringValue(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return ""
    }
}

struct MihomoConnectionActivity: Identifiable, Hashable {
    let connection: MihomoConnection
    let uploadSpeed: Int64
    let downloadSpeed: Int64

    var id: String { connection.id }
    var totalSpeed: Int64 { uploadSpeed + downloadSpeed }
}

struct MihomoControllerQueryItem: Codable {
    let name: String
    let value: String?
}

struct MihomoControllerRequest: Codable {
    let path: String
    let method: String
    let controllerPort: Int
    let controllerSecret: String
    let body: Data?
    let queryItems: [MihomoControllerQueryItem]
}

struct MihomoControllerResponse: Codable {
    let statusCode: Int?
    let body: Data
    let errorMessage: String?
}

enum LogSource: String, Codable, CaseIterable {
    case app
    case core

    var displayName: String { rawValue.capitalized }
}

enum LogLevel: String, Codable {
    case debug
    case info
    case warning
    case error

    var displayName: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let source: LogSource
    let module: String
    let level: LogLevel
    let message: String

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case module
        case level
        case message
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: LogSource,
        module: String,
        level: LogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.module = module
        self.level = level
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(LogSource.self, forKey: .source)
        module = try container.decodeIfPresent(String.self, forKey: .module) ?? source.displayName
        level = try container.decode(LogLevel.self, forKey: .level)
        message = try container.decode(String.self, forKey: .message)
    }
}

enum ExternalResourceKind: String, Codable, CaseIterable {
    case proxyProvider
    case ruleProvider

    var displayName: String {
        switch self {
        case .proxyProvider: "Proxy Providers"
        case .ruleProvider: "Rule Providers"
        }
    }
}

struct ExternalResource: Codable, Identifiable, Hashable {
    let id: String
    let kind: ExternalResourceKind
    let name: String
    let providerType: String
    let path: String
    let url: String?
    let behavior: String?
    let isPresent: Bool
}

enum TunnelProviderOperation: String, Codable {
    case controller
    case coreLogs
    case proxyGroupOrder
    case externalResources
    case readExternalResource
    case writeExternalResource
}

struct TunnelProviderRequest: Codable {
    let operation: TunnelProviderOperation
    let controllerRequest: MihomoControllerRequest?
    let resourceIdentifier: String?
    let resourceContents: Data?
    let path: String?
    let method: String?
    let controllerPort: Int?
    let controllerSecret: String?
    let body: Data?
    let queryItems: [MihomoControllerQueryItem]?

    init(
        operation: TunnelProviderOperation,
        controllerRequest: MihomoControllerRequest? = nil,
        resourceIdentifier: String? = nil,
        resourceContents: Data? = nil
    ) {
        self.operation = operation
        self.controllerRequest = controllerRequest
        self.resourceIdentifier = resourceIdentifier
        self.resourceContents = resourceContents
        path = controllerRequest?.path
        method = controllerRequest?.method
        controllerPort = controllerRequest?.controllerPort
        controllerSecret = controllerRequest?.controllerSecret
        body = controllerRequest?.body
        queryItems = controllerRequest?.queryItems
    }
}

struct TunnelProviderResponse: Codable {
    let controllerResponse: MihomoControllerResponse?
    let coreLogs: [LogEntry]?
    let proxyGroupOrder: [String]?
    let externalResources: [ExternalResource]?
    let resourceContents: Data?
    let errorMessage: String?
}

enum ClientError: LocalizedError {
    case appGroupUnavailable
    case storageUnavailable
    case invalidProfile
    case missingProfile
    case invalidSubscriptionResponse
    case httpFailure(Int)
    case coreUnavailable
    case tunnelUnavailable
    case controllerRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The App Group container is unavailable. Check the signing capabilities."
        case .storageUnavailable:
            "The app's private storage container is unavailable."
        case .invalidProfile:
            "The profile is empty or invalid."
        case .missingProfile:
            "The selected profile no longer exists."
        case .invalidSubscriptionResponse:
            "The subscription did not return a UTF-8 configuration."
        case let .httpFailure(status):
            "The server returned HTTP \(status)."
        case .coreUnavailable:
            "No mihomo bridge is linked to the Packet Tunnel extension."
        case .tunnelUnavailable:
            "The Packet Tunnel is not connected."
        case let .controllerRequestFailed(message):
            message
        }
    }
}
