import Combine
import Foundation
import NetworkExtension
import Yams

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = ClientSnapshot.empty()
    @Published private(set) var tunnelStatus: NEVPNStatus = .invalid
    @Published private(set) var proxyGroups: [MihomoProxyGroup] = []
    @Published private(set) var delays: [String: Int] = [:]
    @Published private(set) var testingProxyGroupIDs: Set<String> = []
    @Published private(set) var testingProxyNodeNames: Set<String> = []
    @Published private(set) var logEntries: [LogEntry] = []
    @Published private(set) var externalResources: [ExternalResource] = []
    @Published private(set) var updatingExternalResourceIDs: Set<String> = []
    @Published private(set) var connectionActivities: [MihomoConnectionActivity] = []
    @Published private(set) var trafficUploadSpeed: Int64 = 0
    @Published private(set) var trafficDownloadSpeed: Int64 = 0
    @Published private(set) var trafficUploadTotal: Int64 = 0
    @Published private(set) var trafficDownloadTotal: Int64 = 0
    @Published private(set) var closingConnectionIDs: Set<String> = []
    @Published private(set) var isClosingAllConnections = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let profiles = SharedProfileRepository()
    private let tunnel = TunnelController()
    private lazy var controller = MihomoControllerClient(tunnel: tunnel)
    private let screenshotDemoMode: Bool
    private var logStore: PersistentLogStore?
    private var demoProfileContents: [UUID: String] = [:]
    private var demoResourceContents: [String: Data] = [:]
    private var coreLogPollingTask: Task<Void, Never>?
    private var connectionPollingTask: Task<Void, Never>?
    private var trafficStreamTask: Task<Void, Never>?
    // ContentView opens the Connection detail by default until the user navigates away.
    private var isConnectionMonitoringEnabled = true
    private var errorDismissalTask: Task<Void, Never>?
    private var reconnectProfile: Profile?
    private var proxyRefreshGeneration = 0
    private var coreLogRefreshGeneration = 0
    private var connectionRefreshGeneration = 0
    private var originalProxyGroupIndices: [String: Int] = [:]
    private var originalProxyCandidateIndices: [String: [String: Int]] = [:]
    private var connectionTransferSamples: [String: ConnectionTransferSample] = [:]

    private static let geoDataLastUpdatedKeyPrefix = "com.swihomo.geodata.lastUpdated."
    private static let appLogLevelKey = "appLogLevel"

    init(demoMode: Bool = ScreenshotDemoMode.isEnabled) {
        screenshotDemoMode = demoMode

        if demoMode {
            let demo = ScreenshotDemoFixtures.make()
            snapshot = demo.snapshot
            tunnelStatus = .connected
            proxyGroups = demo.proxyGroups
            delays = demo.delays
            logEntries = demo.logEntries
            externalResources = demo.externalResources
            connectionActivities = demo.connectionActivities
            trafficUploadSpeed = demo.trafficUploadSpeed
            trafficDownloadSpeed = demo.trafficDownloadSpeed
            trafficUploadTotal = demo.trafficUploadTotal
            trafficDownloadTotal = demo.trafficDownloadTotal
            demoProfileContents = demo.profileContents
            demoResourceContents = demo.resourceContents
            recordOriginalProxyOrder(demo.proxyGroups)
        }

        tunnel.onStartFailed = { [weak self] error in
            guard self?.screenshotDemoMode != true else { return }
            self?.reconnectProfile = nil
            self?.present(error, module: "Mihomo")
        }
        tunnel.onStatusChanged = { [weak self] status in
            guard self?.screenshotDemoMode != true else { return }
            self?.tunnelStatus = status
            self?.record(.info, module: "Tunnel", "Status changed to \(status.rawValue).")
            if status == .connected {
                Task {
                    #if os(macOS)
                    self?.startTrafficStream()
                    #endif
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
                #if os(macOS)
                self?.stopTrafficStream()
                #endif
                self?.connectionPollingTask?.cancel()
                self?.connectionPollingTask = nil
                self?.proxyRefreshGeneration += 1
                self?.connectionRefreshGeneration += 1
                self?.proxyGroups = []
                self?.delays = [:]
                self?.testingProxyGroupIDs = []
                self?.testingProxyNodeNames = []
                self?.originalProxyGroupIndices = [:]
                self?.originalProxyCandidateIndices = [:]
                self?.externalResources = []
                self?.connectionActivities = []
                self?.connectionTransferSamples = [:]
                self?.closingConnectionIDs = []
                self?.isClosingAllConnections = false

                if (status == .disconnected || status == .invalid), let profile = self?.reconnectProfile {
                    self?.reconnectProfile = nil
                    Task { await self?.connect(profile: profile) }
                }
            }
        }
    }

    deinit {
        coreLogPollingTask?.cancel()
        connectionPollingTask?.cancel()
        trafficStreamTask?.cancel()
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

    var connectionStatusLocalizationKey: String {
        switch tunnelStatus {
        case .connected: "status.connected"
        case .connecting, .reasserting: "status.connecting"
        case .disconnecting: "status.disconnecting"
        default: "status.notConnected"
        }
    }

    func load() async {
        guard !screenshotDemoMode else { return }
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
            #if os(macOS)
            if tunnelStatus == .connected {
                startTrafficStream()
            }
            #endif
            record(.info, module: "Lifecycle", "Loaded profile store and Packet Tunnel configuration.")
        } catch {
            present(error, module: "Lifecycle")
        }
    }

    func addLocalProfile(name: String, contents: String) async {
        if screenshotDemoMode {
            let profile = Profile(
                id: UUID(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Demo Local Profile" : name,
                source: .local,
                remoteURL: nil,
                customUserAgent: nil,
                createdAt: .now,
                updatedAt: .now,
                lastFetchedAt: nil,
                subscriptionInfo: nil
            )
            snapshot.profiles.append(profile)
            demoProfileContents[profile.id] = contents
            return
        }
        await perform(module: "Profiles", "Imported local profile \(name).") { [self] in
            snapshot = try await profiles.createLocalProfile(name: name, contents: contents)
        }
    }

    func addRemoteProfile(name: String, url: URL, customUserAgent: String?) async {
        if screenshotDemoMode {
            let profile = Profile(
                id: UUID(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? "Demo Online Profile") : name,
                source: .remote,
                remoteURL: url,
                customUserAgent: customUserAgent,
                createdAt: .now,
                updatedAt: .now,
                lastFetchedAt: .now,
                subscriptionInfo: MihomoSubscriptionInfo(
                    upload: 1_000_000_000,
                    download: 4_000_000_000,
                    total: 20_000_000_000,
                    expire: 1_800_000_000
                )
            )
            snapshot.profiles.append(profile)
            demoProfileContents[profile.id] = "proxies:\n  - name: Demo Node\n    type: http\n    server: demo.example.test\n    port: 443\n"
            return
        }
        await perform(module: "Profiles", "Added online profile \(name).") { [self] in
            snapshot = try await profiles.createRemoteProfile(
                name: name,
                remoteURL: url,
                customUserAgent: customUserAgent
            )
        }
    }

    func refreshProfile(_ profile: Profile) async {
        if screenshotDemoMode { return }
        await perform(module: "Profiles", "Refreshed profile \(profile.name).") { [self] in
            snapshot = try await profiles.refreshProfile(profile.id)
        }
    }

    func updateRemoteProfile(_ profile: Profile, name: String, url: URL, customUserAgent: String?) async {
        if screenshotDemoMode {
            guard let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            snapshot.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (url.host ?? "Demo Online Profile")
                : name
            snapshot.profiles[index].remoteURL = url
            snapshot.profiles[index].customUserAgent = customUserAgent
            snapshot.profiles[index].updatedAt = .now
            return
        }
        await perform(module: "Profiles", "Updated online profile \(name).") { [self] in
            snapshot = try await profiles.updateRemoteProfile(
                profile.id,
                name: name,
                remoteURL: url,
                customUserAgent: customUserAgent
            )
        }
    }

    func profileContents(_ profile: Profile) async -> String? {
        if screenshotDemoMode {
            return demoProfileContents[profile.id]
        }
        do {
            return try await profiles.profileContents(for: profile.id)
        } catch {
            present(error, module: "Profiles")
            return nil
        }
    }

    func saveProfileContents(_ contents: String, for profile: Profile) async -> Bool {
        if screenshotDemoMode {
            guard snapshot.profiles.contains(where: { $0.id == profile.id }) else { return false }
            demoProfileContents[profile.id] = contents
            if let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) {
                snapshot.profiles[index].updatedAt = .now
            }
            return true
        }
        do {
            snapshot = try await profiles.updateProfileContents(contents, for: profile.id)
            record(.info, module: "Profiles", "Saved profile contents for \(profile.name).")
            return true
        } catch {
            present(error, module: "Profiles")
            return false
        }
    }

    func setCustomOverridesEnabled(_ isEnabled: Bool, for profile: Profile) async {
        if screenshotDemoMode {
            guard let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            snapshot.profiles[index].customOverridesEnabled = isEnabled
            return
        }
        let action = isEnabled ? "Enabled" : "Disabled"
        await perform(module: "Profiles", "\(action) custom overrides for \(profile.name).") { [self] in
            snapshot = try await profiles.setCustomOverridesEnabled(isEnabled, for: profile.id)
        }
    }

    func setProfileCustomOverride(_ contents: String, for profile: Profile) async {
        if screenshotDemoMode {
            guard let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            snapshot.profiles[index].customOverrideYAML = contents
            return
        }
        await perform(module: "Profiles", "Saved custom override for \(profile.name).") { [self] in
            snapshot = try await profiles.setCustomOverrideYAML(contents, for: profile.id)
        }
    }

    func deleteProfile(_ profile: Profile) async {
        if screenshotDemoMode {
            snapshot.profiles.removeAll { $0.id == profile.id }
            if snapshot.activeProfileID == profile.id {
                snapshot.activeProfileID = snapshot.profiles.first?.id
            }
            demoProfileContents[profile.id] = nil
            return
        }
        await perform(module: "Profiles", "Deleted profile \(profile.name).") { [self] in
            snapshot = try await profiles.deleteProfile(profile.id)
        }
    }

    func connect(profile: Profile) async {
        if screenshotDemoMode {
            guard snapshot.profiles.contains(where: { $0.id == profile.id }) else { return }
            snapshot.activeProfileID = profile.id
            return
        }
        if tunnelStatus != .disconnected && tunnelStatus != .invalid {
            reconnectProfile = profile
            record(.info, module: "Tunnel", "Switching Packet Tunnel to \(profile.name).")
            if tunnelStatus != .disconnecting {
                tunnel.disconnect()
            }
            return
        }

        await perform(module: "Tunnel", "Requested Packet Tunnel start for \(profile.name).") { [self] in
            snapshot = try await profiles.activateProfile(profile.id)
            let runtime = try await profiles.runtimeConfiguration(for: profile.id)
            let profileContents = try ProfileOverrideComposer.profileContents(
                baseContents: runtime.contents,
                globalOverrides: runtime.profile.customOverridesEnabled ? runtime.overrides.customYAML : "",
                profileOverrides: runtime.profile.customOverrideYAML,
                standardOverrides: MihomoConfigurationBuilder.standardOverridesYAML(runtime.overrides)
            )
            let configuration = try MihomoConfigurationBuilder.makeRuntimeConfiguration(
                profileContents: profileContents
            )
            try await tunnel.connect(
                profileID: profile.id,
                configuration: configuration,
                dnsEnabled: runtime.overrides.dnsEnabled
            )
        }
    }

    func disconnect() {
        if screenshotDemoMode { return }
        reconnectProfile = nil
        record(.info, module: "Tunnel", "Requested disconnect.")
        tunnel.disconnect()
    }

    func reconnect() {
        if screenshotDemoMode { return }
        guard tunnelStatus == .connected, let profile = snapshot.activeProfile else { return }
        reconnectProfile = profile
        record(.info, module: "Tunnel", "Requested reconnect.")
        tunnel.disconnect()
    }

    func dismissError() {
        errorDismissalTask?.cancel()
        errorDismissalTask = nil
        errorMessage = nil
    }

    func saveOverrides(_ overrides: ProxyOverrides) async -> Bool {
        if screenshotDemoMode {
            snapshot.overrides = overrides
            return true
        }
        let previousOverrides = snapshot.overrides
        do {
            snapshot = try await profiles.saveOverrides(overrides)
            record(.info, module: "Configuration", "Saved runtime overrides.")
            guard tunnelStatus == .connected else { return true }

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
            return true
        } catch {
            present(error, module: "Configuration")
            return false
        }
    }

    func reloadProxyGroups(showErrors: Bool = true) async {
        guard !screenshotDemoMode else { return }
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
        if screenshotDemoMode {
            guard let index = proxyGroups.firstIndex(where: { $0.id == group.id }) else { return }
            let current = proxyGroups[index]
            guard current.candidates.contains(node) else { return }
            proxyGroups[index] = MihomoProxyGroup(
                name: current.name,
                selected: node,
                candidates: current.candidates
            )
            return
        }
        await perform(module: "Proxies", "Selected \(node) for \(group.name).") { [self] in
            try await controller.select(node: node, in: group.name, using: snapshot.overrides)
            await reloadProxyGroups(showErrors: false)
        }
    }

    func testDelay(for node: String) async {
        if screenshotDemoMode { return }
        guard testingProxyNodeNames.insert(node).inserted else { return }
        defer { testingProxyNodeNames.remove(node) }
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
        if screenshotDemoMode { return }
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
        if screenshotDemoMode {
            if let source {
                logEntries.removeAll { $0.source == source }
            } else {
                logEntries = []
            }
            return
        }
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
        guard !screenshotDemoMode else { return }
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
        if screenshotDemoMode {
            guard connectionActivities.contains(where: { $0.id == id }) else { return false }
            connectionActivities.removeAll { $0.id == id }
            return true
        }
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
        if screenshotDemoMode {
            connectionActivities = []
            return
        }
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
        if screenshotDemoMode {
            return demoResourceContents[resource.id]
        }
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
        if screenshotDemoMode {
            demoResourceContents[resource.id] = contents
            return true
        }
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Resources")
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await tunnel.writeExternalResource(identifier: resource.id, contents: contents)
            await reloadExternalResources(showErrors: false)
            let nextStep = resource.kind == .geoData
                ? "Reconnect to load the changes."
                : "Use Update to load the changes."
            record(.info, module: "Resources", "Saved external resource \(resource.name). \(nextStep)")
            return true
        } catch {
            present(error, module: "Resources")
            return false
        }
    }

    func updateExternalResource(_ resource: ExternalResource) async {
        if screenshotDemoMode { return }
        guard tunnelStatus == .connected else {
            present(ClientError.tunnelUnavailable, module: "Resources")
            return
        }
        guard updatingExternalResourceIDs.insert(resource.id).inserted else { return }
        defer { updatingExternalResourceIDs.remove(resource.id) }

        do {
            if resource.kind == .geoData {
                try await controller.updateGeoData(using: snapshot.overrides)
                recordGeoDataUpdate(at: .now)
                record(.info, module: "Resources", "Updated enabled geodata databases.")
            } else {
                try await controller.updateExternalResource(resource, using: snapshot.overrides)
                await reloadProxyGroups(showErrors: false)
                record(.info, module: "Resources", "Updated external resource \(resource.name).")
            }
            await reloadExternalResources(showErrors: false)
        } catch {
            present(error, module: "Resources")
        }
    }

    private func reloadCoreLogs(showErrors: Bool) async {
        guard !screenshotDemoMode else { return }
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
        guard !screenshotDemoMode else { return }
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
        guard !screenshotDemoMode else { return }
        guard tunnelStatus == .connected else {
            externalResources = []
            return
        }
        do {
            let resources = try await tunnel.externalResources()
            let providerDetails = (try? await controller.externalResourceDetails(using: snapshot.overrides)) ?? [:]
            externalResources = resources.map { resource in
                var resource = resource
                if let details = providerDetails[resource.id] {
                    resource.updatedAt = details.updatedAt
                    resource.subscriptionInfo = details.subscriptionInfo
                    resource.ruleCount = details.ruleCount
                }
                if resource.kind == .geoData,
                   let lastUpdated = UserDefaults.standard.object(forKey: Self.geoDataLastUpdatedKey(resource.id)) as? Date,
                   lastUpdated > (resource.updatedAt ?? .distantPast) {
                    resource.updatedAt = lastUpdated
                }
                return resource
            }
            record(.debug, module: "Resources", "Loaded \(externalResources.count) external resources.")
        } catch where showErrors {
            present(error, module: "Resources")
        } catch {
            // A pre-IPC extension cannot return external resources until it is reconnected.
        }
    }

    private func startCoreLogPolling() {
        guard !screenshotDemoMode else { return }
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
        guard !screenshotDemoMode else { return }
        connectionPollingTask?.cancel()
        connectionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadConnections(showErrors: false)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    #if os(macOS)
    private func startTrafficStream() {
        guard !screenshotDemoMode else { return }
        trafficStreamTask?.cancel()
        trafficStreamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.tunnelStatus == .connected else { return }
                await self.consumeTrafficStream()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopTrafficStream() {
        trafficStreamTask?.cancel()
        trafficStreamTask = nil
        trafficUploadSpeed = 0
        trafficDownloadSpeed = 0
        trafficUploadTotal = 0
        trafficDownloadTotal = 0
    }

    private func consumeTrafficStream() async {
        guard !screenshotDemoMode else { return }
        let overrides = snapshot.overrides
        guard let url = URL(string: "http://127.0.0.1:\(overrides.controllerPort)/traffic") else { return }
        var request = URLRequest(url: url)
        if !overrides.controllerSecret.isEmpty {
            request.setValue("Bearer \(overrides.controllerSecret)", forHTTPHeaderField: "Authorization")
        }
        let decoder = JSONDecoder()
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let frame = try? decoder.decode(MihomoTrafficFrame.self, from: Data(line.utf8)) else { continue }
                trafficUploadSpeed = frame.up
                trafficDownloadSpeed = frame.down
                trafficUploadTotal = frame.upTotal
                trafficDownloadTotal = frame.downTotal
            }
        } catch {
            // The stream drops when the core restarts; the outer loop reconnects.
        }
    }
    #endif

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

    private func recordGeoDataUpdate(at date: Date) {
        for resource in externalResources where resource.kind == .geoData {
            UserDefaults.standard.set(date, forKey: Self.geoDataLastUpdatedKey(resource.id))
        }
    }

    private static func geoDataLastUpdatedKey(_ resourceID: String) -> String {
        geoDataLastUpdatedKeyPrefix + resourceID
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
        record(.error, module: module, detailedError(error, message: message))
        guard !(error is ProfileOverrideError) else { return }
        errorDismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
            self?.errorDismissalTask = nil
        }
    }

    private func record(_ level: LogLevel, module: String, _ message: String) {
        let appLogLevel = LogLevel(rawValue: UserDefaults.standard.string(forKey: Self.appLogLevelKey) ?? "") ?? .info
        guard appLogLevel.includes(level) else { return }
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
        if let overrideError = error as? ProfileOverrideError,
           let yamlSource = overrideError.yamlSource,
           let yamlDiagnostic = overrideError.yamlDiagnostic {
            details.append("yamlSource=\(yamlSource)")
            details.append("yamlDiagnostic=\(yamlDiagnostic)")
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

private enum ProfileOverrideComposer {
    private enum MergeMode: Equatable {
        case deepMerge
        case forceReplace
        case prepend
        case append
    }

    static func profileContents(
        baseContents: String,
        globalOverrides: String,
        profileOverrides: String,
        standardOverrides: String
    ) throws -> String {
        var profile = try mapping(from: baseContents, description: "profile configuration")
        try merge(contents: globalOverrides, into: &profile, description: "global custom overrides")
        try merge(contents: profileOverrides, into: &profile, description: "profile custom overrides")
        try merge(contents: standardOverrides, into: &profile, description: "standard overrides")
        return try dump(object: profile)
    }

    private static func merge(contents: String, into base: inout [String: Any], description: String) throws {
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        merge(try mapping(from: contents, description: description), into: &base)
    }

    private static func mapping(from contents: String, description: String) throws -> [String: Any] {
        let document: Any?
        do {
            document = try load(yaml: contents)
        } catch {
            throw ProfileOverrideError(yamlSource: description, underlyingError: error)
        }
        guard let mapping = document as? [String: Any] else {
            throw ProfileOverrideError(message: "The \(description) must contain a YAML mapping.")
        }
        return mapping
    }

    // This mirrors mihomo's override merge behavior before standard fields are applied.
    private static func merge(_ overlay: [String: Any], into base: inout [String: Any]) {
        for (rawKey, overlayValue) in overlay {
            let (key, mode) = mergeKey(rawKey)
            if mode == .deepMerge,
               var baseMapping = base[key] as? [String: Any],
               let overlayMapping = overlayValue as? [String: Any] {
                merge(overlayMapping, into: &baseMapping)
                base[key] = baseMapping
                continue
            }
            if (mode == .prepend || mode == .append),
               let baseItems = base[key] as? [Any],
               let overlayItems = overlayValue as? [Any] {
                base[key] = mode == .prepend ? overlayItems + baseItems : baseItems + overlayItems
                continue
            }
            base[key] = overlayValue
        }
    }

    private static func mergeKey(_ rawKey: String) -> (String, MergeMode) {
        if rawKey.hasPrefix("+") {
            return (unescapedKey(String(rawKey.dropFirst())), .prepend)
        }
        if rawKey.hasSuffix("+") {
            return (unescapedKey(String(rawKey.dropLast())), .append)
        }
        if rawKey.hasSuffix("!") {
            return (unescapedKey(String(rawKey.dropLast())), .forceReplace)
        }
        return (unescapedKey(rawKey), .deepMerge)
    }

    private static func unescapedKey(_ key: String) -> String {
        guard key.count > 2, key.hasPrefix("<"), key.hasSuffix(">") else { return key }
        return String(key.dropFirst().dropLast())
    }
}

private struct ProfileOverrideError: LocalizedError {
    let message: String
    let yamlSource: String?
    let yamlDiagnostic: String?

    init(message: String) {
        self.message = message
        yamlSource = nil
        yamlDiagnostic = nil
    }

    init(yamlSource: String, underlyingError: Error) {
        let diagnostic = String(describing: underlyingError)
        message = "Invalid YAML in \(yamlSource).\n\(diagnostic)"
        self.yamlSource = yamlSource
        yamlDiagnostic = diagnostic
    }

    var errorDescription: String? { message }
}
