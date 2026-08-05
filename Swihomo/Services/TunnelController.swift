import Foundation
import NetworkExtension

@MainActor
final class TunnelController {
    static let providerBundleIdentifier = "com.swihomo.client.PacketTunnel"

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var isStarting = false

    private(set) var status: NEVPNStatus = .invalid {
        didSet { onStatusChanged?(status) }
    }
    var onStatusChanged: ((NEVPNStatus) -> Void)?
    var onStartFailed: ((Error) -> Void)?

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    func prepare() async throws {
        let managers = try await NETunnelProviderManager.loadAll()
        let manager = managers.first { manager in
            (manager.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == Self.providerBundleIdentifier
        } ?? NETunnelProviderManager()

        self.manager = manager
        observe(manager)
        status = manager.connection.status
    }

    func connect(
        profileID: UUID,
        configuration: MihomoRuntimeConfiguration,
        dnsEnabled: Bool
    ) async throws {
        if manager == nil {
            try await prepare()
        }
        guard let manager else { return }

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = Self.providerBundleIdentifier
        tunnelProtocol.serverAddress = "Swihomo"
        let includeAllNetworks = packetTunnelIncludeAllNetworks
        tunnelProtocol.includeAllNetworks = includeAllNetworks
        tunnelProtocol.excludeCellularServices = includeAllNetworks && packetTunnelExcludeCellularServices
        tunnelProtocol.excludeLocalNetworks = includeAllNetworks && bypassesPrivateNetworks
        tunnelProtocol.providerConfiguration = [
            "profileID": profileID.uuidString,
            "profileYAML": configuration.profileYAML,
            "dnsEnabled": NSNumber(value: dnsEnabled),
            "automaticallyReclaimsMemory": NSNumber(value: automaticallyReclaimsMemory),
            "bypassedCIDRs": bypassedCIDRs,
            "mtu": NSNumber(value: mtu),
            "customDNSServers": customDNSServers,
            "ipv6Enabled": NSNumber(value: ipv6Enabled)
        ]
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Swihomo"
        manager.isEnabled = true

        try await manager.save()
        try await manager.load()
        observe(manager)
        status = manager.connection.status
        isStarting = true
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            isStarting = false
            throw error
        }
    }

    private var automaticallyReclaimsMemory: Bool {
        UserDefaults.standard.object(forKey: "automaticallyReclaimsMemory") as? Bool ?? false
    }

    private var bypassesPrivateNetworks: Bool {
        UserDefaults.standard.object(forKey: "packetTunnelBypassesPrivateNetworks") as? Bool ?? false
    }

    private var bypassedCIDRs: [String] {
        let rawValue = UserDefaults.standard.string(forKey: "packetTunnelBypassCIDRs") ?? ""
        return rawValue
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var mtu: Int {
        let value = UserDefaults.standard.object(forKey: "packetTunnelMTU") as? Int ?? PacketTunnelMTULimits.defaultValue
        return min(max(value, PacketTunnelMTULimits.minimum), PacketTunnelMTULimits.maximum)
    }

    private var customDNSServers: [String] {
        let rawValue = UserDefaults.standard.string(forKey: "packetTunnelCustomDNSServers") ?? ""
        return rawValue
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var ipv6Enabled: Bool {
        UserDefaults.standard.object(forKey: "packetTunnelIPv6Enabled") as? Bool ?? true
    }

    private var packetTunnelExcludeCellularServices: Bool {
        UserDefaults.standard.object(forKey: "packetTunnelExcludeCellularServices") as? Bool ?? true
    }

    private var packetTunnelIncludeAllNetworks: Bool {
        UserDefaults.standard.object(forKey: "packetTunnelIncludeAllNetworks") as? Bool ?? false
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func controllerResponse(for request: MihomoControllerRequest) async throws -> MihomoControllerResponse {
        let response = try await sendProviderRequest(
            TunnelProviderRequest(operation: .controller, controllerRequest: request)
        )
        guard let controllerResponse = response.controllerResponse else {
            throw ClientError.controllerRequestFailed("The Packet Tunnel did not return a controller response.")
        }
        return controllerResponse
    }

    func coreLogs() async throws -> [LogEntry] {
        let response = try await sendProviderRequest(
            TunnelProviderRequest(operation: .coreLogs, controllerRequest: nil)
        )
        return response.coreLogs ?? []
    }

    func clearCoreLogs() async throws {
        _ = try await sendProviderRequest(
            TunnelProviderRequest(operation: .clearCoreLogs)
        )
    }

    func proxyGroupOrder() async throws -> [String] {
        let response = try await sendProviderRequest(
            TunnelProviderRequest(operation: .proxyGroupOrder)
        )
        return response.proxyGroupOrder ?? []
    }

    func externalResources() async throws -> [ExternalResource] {
        let response = try await sendProviderRequest(
            TunnelProviderRequest(operation: .externalResources)
        )
        return response.externalResources ?? []
    }

    func readExternalResource(identifier: String) async throws -> Data {
        let response = try await sendProviderRequest(
            TunnelProviderRequest(
                operation: .readExternalResource,
                resourceIdentifier: identifier
            )
        )
        guard let contents = response.resourceContents else {
            throw ClientError.controllerRequestFailed("The Packet Tunnel did not return external resource contents.")
        }
        return contents
    }

    func writeExternalResource(identifier: String, contents: Data) async throws {
        _ = try await sendProviderRequest(
            TunnelProviderRequest(
                operation: .writeExternalResource,
                resourceIdentifier: identifier,
                resourceContents: contents
            )
        )
    }

    private func sendProviderRequest(_ request: TunnelProviderRequest) async throws -> TunnelProviderResponse {
        let message = try JSONEncoder().encode(request)
        let responseData = try await sendProviderMessage(message)
        let decoder = JSONDecoder()

        // A running pre-IPC extension accepts the flattened controller fields.
        if let legacyResponse = try? decoder.decode(MihomoControllerResponse.self, from: responseData) {
            switch request.operation {
            case .controller:
                return TunnelProviderResponse(
                    controllerResponse: legacyResponse,
                    coreLogs: nil,
                    proxyGroupOrder: nil,
                    externalResources: nil,
                    resourceContents: nil,
                    errorMessage: nil
                )
            case .coreLogs, .clearCoreLogs, .proxyGroupOrder, .externalResources, .readExternalResource, .writeExternalResource:
                throw ClientError.controllerRequestFailed(
                    "This operation requires reconnecting the Packet Tunnel with the current extension build."
                )
            }
        }

        let response = try decoder.decode(TunnelProviderResponse.self, from: responseData)
        if let errorMessage = response.errorMessage {
            throw ClientError.controllerRequestFailed(errorMessage)
        }
        return response
    }

    private func sendProviderMessage(_ message: Data) async throws -> Data {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else {
            throw ClientError.tunnelUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { response in
                    guard let response else {
                        continuation.resume(throwing: ClientError.tunnelUnavailable)
                        return
                    }
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func observe(_ manager: NETunnelProviderManager) {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        guard let manager else { return }
        status = manager.connection.status

        if status == .connected {
            isStarting = false
            return
        }
        guard isStarting, status == .disconnected || status == .invalid else { return }
        isStarting = false
        Task { [weak self] in
            guard let self, let error = await self.lastDisconnectError() else { return }
            self.onStartFailed?(error)
        }
    }

    private func lastDisconnectError() async -> Error? {
        guard let manager else { return nil }
        return await withCheckedContinuation { continuation in
            manager.connection.fetchLastDisconnectError { error in
                continuation.resume(returning: error)
            }
        }
    }
}

private extension NETunnelProviderManager {
    static func loadAll() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    func save() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
