import Combine
import Foundation
import NetworkExtension

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = ClientSnapshot.empty()
    @Published private(set) var tunnelStatus: NEVPNStatus = .invalid
    @Published private(set) var proxyGroups: [MihomoProxyGroup] = []
    @Published private(set) var delays: [String: Int] = [:]
    @Published private(set) var testingProxyGroupIDs: Set<String> = []
    @Published private(set) var logEntries: [LogEntry] = []
    @Published private(set) var externalResources: [ExternalResource] = []
    @Published private(set) var updatingExternalResourceIDs: Set<String> = []
    @Published private(set) var connectionActivities: [MihomoConnectionActivity] = []
    @Published private(set) var closingConnectionIDs: Set<String> = []
    @Published private(set) var isClosingAllConnections = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let profiles = SharedProfileRepository()
    private let tunnel = TunnelController()
    private lazy var controller = MihomoControllerClient(tunnel: tunnel)
    private var logStore: PersistentLogStore?
    private var coreLogPollingTask: Task<Void, Never>?
    private var connectionPollingTask: Task<Void, Never>?
    // ContentView opens the Connection detail by default until the user navigates away.
    private var isConnectionMonitoringEnabled = true
    private var errorDismissalTask: Task<Void, Never>?
    private var proxyRefreshGeneration = 0
    private var coreLogRefreshGeneration = 0
    private var connectionRefreshGeneration = 0
    private var originalProxyGroupIndices: [String: Int] = [:]
    private var originalProxyCandidateIndices: [String: [String: Int]] = [:]
    private var connectionTransferSamples: [String: ConnectionTransferSample] = [:]

    init() {
        tunnel.onStatusChanged = { [weak self] status in
            self?.tunnelStatus = status
            self?.record(.info, module: "Tunnel", "Status changed to \(status.rawValue).")
            if status == .connected {
                Task {
                    self?.startCoreLogPolling()
                    if self?.isConnectionMonitoringEnabled == true {
                        self?.startConnectionPolling()
                    }
                    await self?.reloadProxyGroupOrder(showErrors: false)
                    await self?.reloadProxyGroups(showErrors: false)
                    await self?.reloadCoreLogs(showErrors: false)
                    await self?.reloadExternalResources(showErrors: false)
                }
            } else {
                self?.coreLogPollingTask?.cancel()
                self?.coreLogPollingTask = nil
                self?.connectionPollingTask?.cancel()
                self?.connectionPollingTask = nil
                self?.proxyRefreshGeneration += 1
                self?.connectionRefreshGeneration += 1
                self?.proxyGroups = []
                self?.delays = [:]
                self?.testingProxyGroupIDs = []
                self?.originalProxyGroupIndices = [:]
                self?.originalProxyCandidateIndices = [:]
                self?.externalResources = []
                self?.connectionActivities = []
                self?.connectionTransferSamples = [:]
                self?.closingConnectionIDs = []
                self?.isClosingAllConnections = false
            }
        }
    }

    deinit {
        coreLogPollingTask?.cancel()
        connectionPollingTask?.cancel()
    }

    var isConnected: Bool { tunnelStatus == .connected || tunnelStatus == .connecting }

    var connectionStatusTitle: String {
        switch tunnelStatus {
        case .connected: "Connected"
        case .connecting, .reasserting: "Connecting"
        case .disconnecting: "Disconnecting"
        default: "Not connected"
        }
    }

    func load() async {
        if logStore == nil {
            let store = await Task.detached(priority: .utility) {
                PersistentLogStore(directoryName: "AppLogs")
            }.value
            logStore = store
            logEntries = store.entries()
        }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await profiles.loadSnapshot()
            try await tunnel.prepare()
            tunnelStatus = tunnel.status
            if tunnelStatus == .connected, isConnectionMonitoringEnabled {
                startConnectionPolling()
            }
            record(.info, module: "Lifecycle", "Loaded profile store and Packet Tunnel configuration.")
        } catch {
            present(error, module: "Lifecycle")
        }
    }

    func addLocalProfile(name: String, contents: String) async {
        await perform(module: "Profiles", "Imported local profile \(name).") { [self] in
            snapshot = try await profiles.createLocalProfile(name: name, contents: contents)
        }
    }

    func addRemoteProfile(name: String, url: URL, customUserAgent: String?) async {
        await perform(module: "Profiles", "Added online profile \(name).") { [self] in
            snapshot = try await profiles.createRemoteProfile(
                name: name,
                remoteURL: url,
                customUserAgent: customUserAgent
            )
        }
    }

    func refreshProfile(_ profile: Profile) async {
        await perform(module: "Profiles", "Refreshed profile \(profile.name).") { [self] in
            snapshot = try await profiles.refreshProfile(profile.id)
        }
    }

    func deleteProfile(_ profile: Profile) async {
        await perform(module: "Profiles", "Deleted profile \(profile.name).") { [self] in
            snapshot = try await profiles.deleteProfile(profile.id)
        }
    }

    func connect(profile: Profile) async {
        await perform(module: "Tunnel", "Started Packet Tunnel for \(profile.name).") { [self] in
            snapshot = try await profiles.activateProfile(profile.id)
            let runtime = try await profiles.runtimeConfiguration(for: profile.id)
            let configuration = try MihomoConfigurationBuilder.makeRuntimeConfiguration(
                profileContents: runtime.contents,
                overrides: runtime.overrides
            )
            try await tunnel.connect(
                profileID: profile.id,
                configuration: configuration,
                dnsEnabled: runtime.overrides.dnsEnabled
            )
        }
    }

    func disconnect() {
        record(.info, module: "Tunnel", "Requested disconnect.")
        tunnel.disconnect()
    }

    func dismissError() {
        errorDismissalTask?.cancel()
        errorDismissalTask = nil
        errorMessage = nil
    }

    func saveOverrides(_ overrides: ProxyOverrides) async {
        let previousOverrides = snapshot.overrides
        await perform(module: "Configuration", "Saved runtime overrides.") { [self] in
            snapshot = try await profiles.saveOverrides(overrides)
            guard tunnelStatus == .connected else { return }

            if previousOverrides.logLevel != overrides.logLevel {
                do {
                    try await controller.updateLogLevel(overrides.logLevel, using: previousOverrides)
                    record(.info, module: "Configuration", "Applied log level to the running core.")
                } catch {
                    record(.warning, module: "Configuration", "Saved log level. Reconnect to apply it to the running core.")
                }
            }

            if previousOverrides.mode != overrides.mode {
                do {
                    try await controller.updateRoutingMode(overrides.mode, using: previousOverrides)
                    record(.info, module: "Configuration", "Applied routing mode to the running core.")
                } catch {
                    record(.warning, module: "Configuration", "Saved routing mode. Reconnect to apply it to the running core.")
                }
            }
        }
    }

    func reloadProxyGroups(showErrors: Bool = true) async {
        guard tunnelStatus == .connected else {
            proxyGroups = []
            delays = [:]
            return
        }

        proxyRefreshGeneration += 1
        let generation = proxyRefreshGeneration
        do {
            let groups = try await controller.proxyGroups(using: snapshot.overrides)
            guard generation == proxyRefreshGeneration else { return }
            recordOriginalProxyOrder(groups)
            proxyGroups = groups
            let candidates = Set(groups.flatMap(\.candidates))
            delays = delays.filter { candidates.contains($0.key) }
            if showErrors {
                record(.info, module: "Proxies", "Loaded \(groups.count) proxy groups.")
            }
        } catch where showErrors && generation == proxyRefreshGeneration {
            present(error, module: "Proxies")
        } catch {
            // The visible Proxies page polls silently while the controller is unavailable.
        }
    }

    func select(node: String, in group: MihomoProxyGroup) async {
        await perform(module: "Proxies", "Selected \(node) for \(group.name).") { [self] in
            try await controller.select(node: node, in: group.name, using: snapshot.overrides)
            await reloadProxyGroups(showErrors: false)
        }
    }

    func testDelay(for node: String) async {
        do {
            if let delay = try await controller.delay(for: node, using: snapshot.overrides) {
                delays[node] = delay
                record(.debug, module: "Proxies", "Delay test for \(node): \(delay) ms.")
            }
        } catch {
            present(error, module: "Proxies")
        }
    }

    func testDelays(in group: MihomoProxyGroup) async {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Proxies")
            return
        }
        guard testingProxyGroupIDs.insert(group.id).inserted else { return }
        defer { testingProxyGroupIDs.remove(group.id) }

        do {
            let groupDelays = try await controller.delays(in: group, using: snapshot.overrides)
            delays.merge(groupDelays) { _, latest in latest }
            await reloadProxyGroups(showErrors: false)
            record(.debug, module: "Proxies", "Delay test for \(group.name): \(groupDelays.count) nodes.")
        } catch {
            present(error, module: "Proxies")
        }
    }

    func sortedProxyGroups(
        by criterion: ProxyGroupSortCriterion,
        direction: ProxySortDirection
    ) -> [MihomoProxyGroup] {
        proxyGroups.sorted { left, right in
            let comparison: ComparisonResult
            switch criterion {
            case .original:
                comparison = integerComparison(originalGroupIndex(for: left), originalGroupIndex(for: right))
            case .name:
                comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            }
            return isOrdered(comparison, direction: direction, fallback: {
                originalGroupIndex(for: left) < originalGroupIndex(for: right)
            })
        }
    }

    func sortedCandidates(
        in group: MihomoProxyGroup,
        by criterion: ProxyNodeSortCriterion,
        direction: ProxySortDirection
    ) -> [String] {
        group.candidates.sorted { left, right in
            let fallback = {
                self.originalCandidateIndex(for: left, in: group) < self.originalCandidateIndex(for: right, in: group)
            }
            switch criterion {
            case .original:
                return isOrdered(
                    integerComparison(
                        originalCandidateIndex(for: left, in: group),
                        originalCandidateIndex(for: right, in: group)
                    ),
                    direction: direction,
                    fallback: fallback
                )
            case .name:
                return isOrdered(
                    left.localizedCaseInsensitiveCompare(right),
                    direction: direction,
                    fallback: fallback
                )
            case .delay:
                switch (delays[left], delays[right]) {
                case let (leftDelay?, rightDelay?):
                    return isOrdered(integerComparison(leftDelay, rightDelay), direction: direction, fallback: fallback)
                case (nil, nil):
                    return fallback()
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
        }
    }

    func sortedConnectionActivities(
        by criterion: ConnectionSortCriterion,
        direction: ProxySortDirection
    ) -> [MihomoConnectionActivity] {
        connectionActivities.sorted { left, right in
            let comparison: ComparisonResult
            switch criterion {
            case .process:
                comparison = left.connection.processName.localizedCaseInsensitiveCompare(right.connection.processName)
            case .speed:
                if left.totalSpeed == right.totalSpeed {
                    comparison = .orderedSame
                } else {
                    comparison = left.totalSpeed < right.totalSpeed ? .orderedAscending : .orderedDescending
                }
            case .rule:
                comparison = left.connection.ruleDescription.localizedCaseInsensitiveCompare(right.connection.ruleDescription)
            }
            return isOrdered(comparison, direction: direction, fallback: { left.id < right.id })
        }
    }

    func reloadLogs() async {
        await reloadCoreLogs(showErrors: true)
    }

    func clearLogs(source: LogSource? = nil) async {
        guard let logStore else { return }

        if source != .app {
            coreLogRefreshGeneration += 1
            guard tunnelStatus == .connected else {
                present(ClientError.tunnelUnavailable, module: "Logs")
                return
            }
            do {
                try await tunnel.clearCoreLogs()
            } catch {
                present(error, module: "Logs")
                return
            }
        }

        logEntries = logStore.clear(source: source)
    }

    func reloadConnections(showErrors: Bool = true) async {
        guard isConnectionMonitoringEnabled, tunnelStatus == .connected else { return }

        connectionRefreshGeneration += 1
        let generation = connectionRefreshGeneration
        do {
            let connections = try await controller.connections(using: snapshot.overrides)
            guard generation == connectionRefreshGeneration else { return }
            updateConnectionActivities(connections, at: Date())
        } catch where showErrors && generation == connectionRefreshGeneration {
            present(error, module: "Connections")
        } catch {
            // The connection dashboard keeps polling while the controller is temporarily unavailable.
        }
    }

    func setConnectionMonitoringEnabled(_ isEnabled: Bool) {
        if isConnectionMonitoringEnabled == isEnabled {
            if isEnabled, tunnelStatus == .connected, connectionPollingTask == nil {
                startConnectionPolling()
            }
            return
        }
        isConnectionMonitoringEnabled = isEnabled

        guard isEnabled, tunnelStatus == .connected else {
            connectionPollingTask?.cancel()
            connectionPollingTask = nil
            connectionRefreshGeneration += 1
            return
        }

        startConnectionPolling()
    }

    func closeConnection(id: String) async -> Bool {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Connections")
            return false
        }
        guard closingConnectionIDs.insert(id).inserted else { return false }
        defer { closingConnectionIDs.remove(id) }

        do {
            try await controller.closeConnection(id: id, using: snapshot.overrides)
            connectionActivities.removeAll { $0.id == id }
            connectionTransferSamples[id] = nil
            record(.info, module: "Connections", "Closed connection \(id).")
            return true
        } catch {
            present(error, module: "Connections")
            return false
        }
    }

    func closeAllConnections() async {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Connections")
            return
        }
        guard !isClosingAllConnections else { return }
        isClosingAllConnections = true
        defer { isClosingAllConnections = false }

        do {
            try await controller.closeAllConnections(using: snapshot.overrides)
            connectionActivities = []
            connectionTransferSamples = [:]
            record(.info, module: "Connections", "Closed all connections.")
        } catch {
            present(error, module: "Connections")
        }
    }

    func reloadExternalResources() async {
        await reloadExternalResources(showErrors: true)
    }

    func externalResourceContents(_ resource: ExternalResource) async -> Data? {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Resources")
            return nil
        }
        do {
            return try await tunnel.readExternalResource(identifier: resource.id)
        } catch {
            present(error, module: "Resources")
            return nil
        }
    }

    func saveExternalResource(_ resource: ExternalResource, contents: Data) async -> Bool {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Resources")
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await tunnel.writeExternalResource(identifier: resource.id, contents: contents)
            await reloadExternalResources(showErrors: false)
            record(.info, module: "Resources", "Saved external resource \(resource.name). Use Update to load the changes.")
            return true
        } catch {
            present(error, module: "Resources")
            return false
        }
    }

    func updateExternalResource(_ resource: ExternalResource) async {
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Resources")
            return
        }
        guard updatingExternalResourceIDs.insert(resource.id).inserted else { return }
        defer { updatingExternalResourceIDs.remove(resource.id) }

        do {
            try await controller.updateExternalResource(resource, using: snapshot.overrides)
            await reloadExternalResources(showErrors: false)
            await reloadProxyGroups(showErrors: false)
            record(.info, module: "Resources", "Updated external resource \(resource.name).")
        } catch {
            present(error, module: "Resources")
        }
    }

    private func reloadCoreLogs(showErrors: Bool) async {
        guard tunnelStatus == .connected, let logStore else { return }
        coreLogRefreshGeneration += 1
        let generation = coreLogRefreshGeneration
        do {
            let coreLogs = try await tunnel.coreLogs()
            guard generation == coreLogRefreshGeneration else { return }
            logEntries = logStore.replace(source: .core, with: coreLogs)
        } catch where showErrors {
            present(error, module: "Logs")
        } catch {
            // A pre-IPC extension cannot return core logs until it is reconnected.
        }
    }

    private func updateConnectionActivities(_ connections: [MihomoConnection], at timestamp: Date) {
        var latestSamples: [String: ConnectionTransferSample] = [:]
        connectionActivities = connections.map { connection in
            let previous = connectionTransferSamples[connection.id]
            let elapsed = timestamp.timeIntervalSince(previous?.timestamp ?? timestamp)
            let uploadSpeed: Int64
            let downloadSpeed: Int64

            if let previous,
               elapsed > 0,
               connection.upload >= previous.upload,
               connection.download >= previous.download {
                uploadSpeed = Int64(Double(connection.upload - previous.upload) / elapsed)
                downloadSpeed = Int64(Double(connection.download - previous.download) / elapsed)
            } else {
                uploadSpeed = 0
                downloadSpeed = 0
            }

            latestSamples[connection.id] = ConnectionTransferSample(
                upload: connection.upload,
                download: connection.download,
                timestamp: timestamp
            )
            return MihomoConnectionActivity(
                connection: connection,
                uploadSpeed: uploadSpeed,
                downloadSpeed: downloadSpeed
            )
        }
        connectionTransferSamples = latestSamples
    }

    private func reloadProxyGroupOrder(showErrors: Bool) async {
        guard tunnelStatus == .connected else { return }
        do {
            let groupOrder = try await tunnel.proxyGroupOrder()
            originalProxyGroupIndices = Dictionary(
                uniqueKeysWithValues: groupOrder.enumerated().map { ($0.element, $0.offset) }
            )
        } catch where showErrors {
            present(error, module: "Proxies")
        } catch {
            // A pre-IPC extension cannot return the profile order until it is reconnected.
        }
    }

    private func reloadExternalResources(showErrors: Bool) async {
        guard tunnelStatus == .connected else {
            externalResources = []
            return
        }
        do {
            externalResources = try await tunnel.externalResources()
            record(.debug, module: "Resources", "Loaded \(externalResources.count) external resources.")
        } catch where showErrors {
            present(error, module: "Resources")
        } catch {
            // A pre-IPC extension cannot return external resources until it is reconnected.
        }
    }

    private func startCoreLogPolling() {
        coreLogPollingTask?.cancel()
        coreLogPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.reloadCoreLogs(showErrors: false)
            }
        }
    }

    private func startConnectionPolling() {
        connectionPollingTask?.cancel()
        connectionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadConnections(showErrors: false)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func recordOriginalProxyOrder(_ groups: [MihomoProxyGroup]) {
        for group in groups {
            if originalProxyGroupIndices[group.id] == nil {
                originalProxyGroupIndices[group.id] = originalProxyGroupIndices.count
            }

            var candidateIndices = originalProxyCandidateIndices[group.id] ?? [:]
            for candidate in group.candidates where candidateIndices[candidate] == nil {
                candidateIndices[candidate] = candidateIndices.count
            }
            originalProxyCandidateIndices[group.id] = candidateIndices
        }
    }

    private func originalGroupIndex(for group: MihomoProxyGroup) -> Int {
        originalProxyGroupIndices[group.id] ?? .max
    }

    private func originalCandidateIndex(for candidate: String, in group: MihomoProxyGroup) -> Int {
        originalProxyCandidateIndices[group.id]?[candidate] ?? .max
    }

    private func isOrdered(
        _ comparison: ComparisonResult,
        direction: ProxySortDirection,
        fallback: () -> Bool
    ) -> Bool {
        switch comparison {
        case .orderedAscending:
            direction == .ascending
        case .orderedDescending:
            direction == .descending
        case .orderedSame:
            fallback()
        }
    }

    private func integerComparison(_ left: Int, _ right: Int) -> ComparisonResult {
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    private func perform(
        module: String,
        _ successMessage: String,
        _ operation: @escaping () async throws -> Void
    ) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await operation()
            record(.info, module: module, successMessage)
        } catch {
            present(error, module: module)
        }
    }

    private func present(_ error: Error, module: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorDismissalTask?.cancel()
        errorMessage = message
        errorDismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
            self?.errorDismissalTask = nil
        }
        record(.error, module: module, detailedError(error, message: message))
    }

    private func record(_ level: LogLevel, module: String, _ message: String) {
        guard let logStore else { return }
        logEntries = logStore.append(source: .app, module: module, level: level, message: message)
    }

    private func detailedError(_ error: Error, message: String) -> String {
        let nsError = error as NSError
        var details = [
            "message=\(message)",
            "type=\(String(reflecting: type(of: error)))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            details.append("reason=\(reason)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlying.domain):\(underlying.code) \(underlying.localizedDescription)")
        }
        if let decodingError = error as? DecodingError {
            details.append(decodingDescription(decodingError))
        }
        return details.joined(separator: " | ")
    }

    private func decodingDescription(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        let kind: String
        switch error {
        case let .dataCorrupted(value):
            context = value
            kind = "dataCorrupted"
        case let .keyNotFound(key, value):
            context = value
            kind = "keyNotFound(\(key.stringValue))"
        case let .typeMismatch(type, value):
            context = value
            kind = "typeMismatch(\(String(reflecting: type)))"
        case let .valueNotFound(type, value):
            context = value
            kind = "valueNotFound(\(String(reflecting: type)))"
        @unknown default:
            return "decoding=unknown"
        }

        let path = context.codingPath
            .map { $0.intValue.map(String.init) ?? $0.stringValue }
            .joined(separator: ".")
        return "decoding=\(kind) path=\(path.isEmpty ? "<root>" : path) debug=\(context.debugDescription)"
    }
}

private struct ConnectionTransferSample {
    let upload: Int64
    let download: Int64
    let timestamp: Date
}
