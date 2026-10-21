import Foundation
import os.log

/// Bridges the syncable subset of `Settings` to iCloud's ubiquitous key-value
/// store. Lives entirely in the app process: the packet tunnel extension never
/// touches iCloud, and screenshot demo mode never starts this controller.
///
/// Sync policy:
/// - The sync configuration itself (`sync.config.*`) always syncs while the
///   master switch is on, so a newly enrolled device immediately learns which
///   content categories the user enabled.
/// - Preference values (`settings.*`) only sync while their category switch is
///   on. Turning a switch off never deletes remote data.
/// - KVS resolves conflicts last-writer-wins per key server-side, so inbound
///   values are simply applied; no local merge is needed.
@MainActor
final class SettingsSyncController: ObservableObject {
    static let shared = SettingsSyncController()

    /// How the user wants an enable-time conflict between the cloud copy and
    /// the local copy of the synced settings resolved.
    enum EnableConflictResolution {
        /// Pull the cloud configuration and values over the local ones.
        case useRemote
        /// Push the local configuration and values over the cloud ones.
        case useLocal
        /// Turn the master switch back off; nothing syncs.
        case cancel
    }

    /// True while an enable-time conflict waits for the user's choice on the
    /// sync settings page. All sync activity is held in the meantime.
    @Published private(set) var pendingEnableConflict = false

    private enum KVSKey {
        static let configProfiles = "sync.config.profiles"
        /// The global overrides switch shares the profiles zone, so its
        /// configuration rides KVS the same way.
        static let configOverrides = "sync.config.overrides"
        /// Retired single-toggle configuration key from the initial sync
        /// design. Never read; removed when deleting all synced data so old
        /// builds stop seeing it too.
        static let legacyConfigPreferences = "sync.config.preferences"
    }

    /// A syncable settings category: one KVS-synced configuration switch plus
    /// the preference values it covers. Profiles sync through CloudKit
    /// instead and are not part of this list.
    fileprivate enum SyncCategory: String, CaseIterable {
        case general
        case sorting
        case network
        case experimental

        var configKey: String { "sync.config.\(rawValue)" }

        func isEnabled(_ settings: Settings) -> Bool {
            settings[keyPath: keyPath]
        }

        func setEnabled(_ enabled: Bool, on settings: inout Settings) {
            settings[keyPath: keyPath] = enabled
        }

        private var keyPath: WritableKeyPath<Settings, Bool> {
            switch self {
            case .general: \.iCloudSyncGeneral
            case .sorting: \.iCloudSyncSorting
            case .network: \.iCloudSyncNetwork
            case .experimental: \.iCloudSyncExperimental
            }
        }
    }

    /// One syncable preference entry: how to export it, how to import it, and
    /// how to tell whether it changed between two settings snapshots.
    fileprivate struct SyncedPreferenceKey {
        let category: SyncCategory
        let kvsKey: String
        let export: (Settings) -> Any
        let isUnchanged: (Settings, Settings) -> Bool
        /// Applies the remote value into `settings` when the key exists.
        /// Returns true when the local value changed.
        let importValue: (inout Settings, NSUbiquitousKeyValueStore) -> Bool
    }

    private static let syncedPreferences: [SyncedPreferenceKey] = [
        // General: appearance, language, log level, subscription display,
        // menu bar style, proxy group folding.
        .stringEnum(.general, "appTheme", \.appTheme),
        .stringEnum(.general, "appLanguage", \.appLanguage),
        .stringEnum(.general, "appLogLevel", \.appLogLevel),
        .stringEnum(.general, "subscriptionInfoDisplay", \.subscriptionInfoDisplay),
        .stringEnum(.general, "menuBarDisplay", \.menuBarDisplay),
        .bool(.general, "autoCollapseProxyGroups", \.autoCollapseProxyGroups),
        // Sorting: connection / proxy group / proxy node order.
        .stringEnum(.sorting, "connectionSortCriterion", \.connectionSortCriterion),
        .stringEnum(.sorting, "connectionSortDirection", \.connectionSortDirection),
        .stringEnum(.sorting, "proxyGroupSortCriterion", \.proxyGroupSortCriterion),
        .stringEnum(.sorting, "proxyGroupSortDirection", \.proxyGroupSortDirection),
        .stringEnum(.sorting, "proxyNodeSortCriterion", \.proxyNodeSortCriterion),
        .stringEnum(.sorting, "proxyNodeSortDirection", \.proxyNodeSortDirection),
        // Network: packet tunnel configuration.
        .int(.network, "packetTunnelMTU", \.packetTunnelMTU,
             range: PacketTunnelMTULimits.minimum...PacketTunnelMTULimits.maximum),
        .bool(.network, "packetTunnelIPv6Enabled", \.packetTunnelIPv6Enabled),
        .stringEnum(.network, "packetTunnelIPStack", \.packetTunnelIPStack),
        .stringEnum(.network, "packetTunnelCongestionController", \.packetTunnelCongestionController),
        .string(.network, "packetTunnelCustomDNSServers", \.packetTunnelCustomDNSServers),
        .bool(.network, "packetTunnelIncludeAllNetworks", \.packetTunnelIncludeAllNetworks),
        .bool(.network, "packetTunnelExcludeCellularServices", \.packetTunnelExcludeCellularServices),
        .bool(.network, "packetTunnelBypassesPrivateNetworks", \.packetTunnelBypassesPrivateNetworks),
        .bool(.network, "packetTunnelBypassAPNs", \.packetTunnelBypassAPNs),
        .string(.network, "packetTunnelBypassCIDRs", \.packetTunnelBypassCIDRs),
        // Experimental: memory reclaim, geo rulesets, delay testing.
        .bool(.experimental, "automaticallyReclaimsMemory", \.automaticallyReclaimsMemory),
        .bool(.experimental, "replaceGeoDatabasesWithRulesets", \.replaceGeoDatabasesWithRulesets),
        .bool(.experimental, "realtimeDelayTest", \.realtimeDelayTest),
        .int(.experimental, "delayTestMaxConcurrency", \.delayTestMaxConcurrency, range: 1...32),
    ]

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.swihomo.client",
        category: "SettingsSync"
    )
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private var settingsStore: SettingsStore?
    private var externalChangeObserver: NSObjectProtocol?
    private var isApplyingRemoteChanges = false
    private var isStarted = false
    /// Set when the user performed a sync action this session. KVS discards
    /// writes made before the first iCloud download, so an InitialSyncChange
    /// arriving on an empty remote store re-publishes them once.
    private var didPushFromUserAction = false

    private init() {}

    func start(store: SettingsStore) {
        guard !isStarted else { return }
        isStarted = true
        settingsStore = store

        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: keyValueStore,
            queue: nil
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleExternalChange(notification)
            }
        }

        performInitialSync()
    }

    /// Removes every value Swihomo has written to the ubiquitous key-value
    /// store, then silences the local content switches without re-publishing
    /// them. Peers observing the removal do the same (see pullConfiguration),
    /// so deleted data is not resurrected. Local settings values themselves
    /// are left untouched.
    func deleteAllSyncedData() {
        guard isStarted, let settingsStore else { return }
        keyValueStore.removeObject(forKey: KVSKey.legacyConfigPreferences)
        keyValueStore.removeObject(forKey: KVSKey.configProfiles)
        keyValueStore.removeObject(forKey: KVSKey.configOverrides)
        for category in SyncCategory.allCases {
            keyValueStore.removeObject(forKey: category.configKey)
        }
        for key in Self.syncedPreferences {
            keyValueStore.removeObject(forKey: key.kvsKey)
        }
        keyValueStore.synchronize()
        var settings = settingsStore.settings
        for category in SyncCategory.allCases {
            category.setEnabled(false, on: &settings)
        }
        settings.iCloudSyncProfiles = false
        settings.iCloudSyncOverrides = false
        applyRemote(settings)
        Task { await ProfileSyncEngine.shared.deleteAllSyncedData() }
        logger.notice("Deleted all settings data from the ubiquitous key-value store.")
        SyncStatusStore.shared.record(String(localized: "icloudSync.status.dataDeleted"))
    }

    // MARK: - Outbound

    /// Called from `SettingsStore.settings.didSet` after the equality gate, so
    /// only real changes arrive here.
    func settingsDidChange(new: Settings, old: Settings) {
        guard isStarted, !isApplyingRemoteChanges else { return }

        if new.iCloudSyncEnabled, !old.iCloudSyncEnabled {
            // Master switch just turned on. When the cloud already holds a
            // sync configuration, merging is the user's call: hold all sync
            // activity until the prompt on the sync settings page resolves.
            keyValueStore.synchronize()
            if remoteHasAnyConfiguration() {
                pendingEnableConflict = true
                return
            }
            adoptRemoteConfiguration()
            return
        }

        guard new.iCloudSyncEnabled else {
            // Master switch off: stop all sync activity, including the profile
            // engine. Content switches keep their values.
            if old.iCloudSyncEnabled {
                notifyProfileSyncEngine()
            }
            return
        }

        let changedCategories = SyncCategory.allCases.filter {
            $0.isEnabled(new) != $0.isEnabled(old)
        }
        if !changedCategories.isEmpty || new.iCloudSyncProfiles != old.iCloudSyncProfiles
            || new.iCloudSyncOverrides != old.iCloudSyncOverrides {
            pushConfiguration(new)
            didPushFromUserAction = true
        }

        // Newly enabled categories pull remote values and reseed keys the
        // remote store has never seen; already-enabled categories push local
        // edits. Turning a category off only stops syncing it.
        if changedCategories.contains(where: { $0.isEnabled(new) }) {
            pullPreferences(reseedMissing: true)
            didPushFromUserAction = true
        } else {
            pushChangedPreferences(new: new, old: old)
        }

        notifyProfileSyncEngine()
    }

    /// Resolves the enable-time conflict shown when the master switch was
    /// turned on while the cloud already held synced settings.
    func resolveEnableConflict(_ resolution: EnableConflictResolution) {
        guard pendingEnableConflict, let settingsStore else { return }
        pendingEnableConflict = false
        switch resolution {
        case .useRemote:
            adoptRemoteConfiguration()
        case .useLocal:
            pushConfiguration(settingsStore.settings)
            pushAllPreferences(settingsStore.settings)
            notifyProfileSyncEngine()
        case .cancel:
            var settings = settingsStore.settings
            settings.iCloudSyncEnabled = false
            // Goes through settingsDidChange, whose master-off branch stops
            // the profile engine.
            settingsStore.settings = settings
        }
    }

    private func remoteHasAnyConfiguration() -> Bool {
        SyncCategory.allCases.contains { remoteBool(forKey: $0.configKey) != nil }
            || remoteBool(forKey: KVSKey.configProfiles) != nil
            || remoteBool(forKey: KVSKey.configOverrides) != nil
    }

    /// Pulls the remote sync configuration and values, then publishes only
    /// the keys the remote store lacks. Used when enabling without a
    /// conflict and when the user picks the cloud copy.
    private func adoptRemoteConfiguration() {
        // Silence local categories first if the remote store was wiped.
        pullConfiguration(remoteDeletionSilencesLocal: true)
        if let settingsStore {
            // Publish only configuration keys the remote store lacks, and
            // never overwrite existing remote values from a possibly
            // stale local cache.
            let settings = settingsStore.settings
            var didPush = false
            for category in SyncCategory.allCases where remoteBool(forKey: category.configKey) == nil {
                keyValueStore.set(category.isEnabled(settings), forKey: category.configKey)
                didPush = true
            }
            if remoteBool(forKey: KVSKey.configProfiles) == nil {
                keyValueStore.set(settings.iCloudSyncProfiles, forKey: KVSKey.configProfiles)
                didPush = true
            }
            if remoteBool(forKey: KVSKey.configOverrides) == nil {
                keyValueStore.set(settings.iCloudSyncOverrides, forKey: KVSKey.configOverrides)
                didPush = true
            }
            if didPush {
                keyValueStore.synchronize()
                didPushFromUserAction = true
                SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPushed"))
            }
            pullPreferences(reseedMissing: true)
        }
        notifyProfileSyncEngine()
    }

    /// Publishes every preference value of the enabled categories,
    /// overwriting remote values: the user chose the local copy.
    private func pushAllPreferences(_ settings: Settings) {
        for key in Self.syncedPreferences where key.category.isEnabled(settings) {
            keyValueStore.set(key.export(settings), forKey: key.kvsKey)
        }
        keyValueStore.synchronize()
        didPushFromUserAction = true
        SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPushed"))
    }

    private func pushConfiguration(_ settings: Settings) {
        for category in SyncCategory.allCases {
            keyValueStore.set(category.isEnabled(settings), forKey: category.configKey)
        }
        keyValueStore.set(settings.iCloudSyncProfiles, forKey: KVSKey.configProfiles)
        keyValueStore.set(settings.iCloudSyncOverrides, forKey: KVSKey.configOverrides)
        keyValueStore.synchronize()
        didPushFromUserAction = true
        SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPushed"))
    }

    private func pushChangedPreferences(new: Settings, old: Settings) {
        var didPush = false
        for key in Self.syncedPreferences
        where key.category.isEnabled(new) && !key.isUnchanged(new, old) {
            keyValueStore.set(key.export(new), forKey: key.kvsKey)
            didPush = true
        }
        if didPush {
            keyValueStore.synchronize()
            didPushFromUserAction = true
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPushed"))
        }
    }

    /// Publishes local values for keys the remote store has never seen, so
    /// enabling sync on a fresh account still uploads this device's setup.
    private func pushMissingPreferences(_ settings: Settings) {
        var didPush = false
        for key in Self.syncedPreferences
        where key.category.isEnabled(settings) && keyValueStore.object(forKey: key.kvsKey) == nil {
            keyValueStore.set(key.export(settings), forKey: key.kvsKey)
            didPush = true
        }
        if didPush {
            keyValueStore.synchronize()
            didPushFromUserAction = true
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPushed"))
        }
    }

    // MARK: - Inbound

    private func performInitialSync() {
        guard let settingsStore, settingsStore.settings.iCloudSyncEnabled else { return }
        keyValueStore.synchronize()
        // At launch a vanished remote configuration means another device
        // deleted the iCloud data while this one was away: fall silent instead
        // of reseeding. Missing preference values are not republished either;
        // they are only reseeded on explicit user action.
        pullConfiguration(remoteDeletionSilencesLocal: true)
        pullPreferences(reseedMissing: false)
    }

    /// Applies the remotely stored sync configuration (content category
    /// switches). Never pushes: outbound configuration writes happen only for
    /// local user actions, so a deleted store stays deleted.
    private func pullConfiguration(remoteDeletionSilencesLocal: Bool = false) {
        guard let settingsStore else { return }
        var settings = settingsStore.settings
        var changed = false
        var sawRemoteConfiguration = false
        for category in SyncCategory.allCases {
            if let value = remoteBool(forKey: category.configKey) {
                sawRemoteConfiguration = true
                if category.isEnabled(settings) != value {
                    category.setEnabled(value, on: &settings)
                    changed = true
                }
            }
        }
        if let value = remoteBool(forKey: KVSKey.configProfiles) {
            sawRemoteConfiguration = true
            if settings.iCloudSyncProfiles != value {
                settings.iCloudSyncProfiles = value
                changed = true
            }
        }
        if let value = remoteBool(forKey: KVSKey.configOverrides) {
            sawRemoteConfiguration = true
            if settings.iCloudSyncOverrides != value {
                settings.iCloudSyncOverrides = value
                changed = true
            }
        }
        var zoneSyncSilencedByDeletion = false
        if remoteDeletionSilencesLocal, !sawRemoteConfiguration {
            let anyCategoryEnabled = SyncCategory.allCases.contains { $0.isEnabled(settings) }
            if anyCategoryEnabled || settings.iCloudSyncProfiles || settings.iCloudSyncOverrides {
                zoneSyncSilencedByDeletion = settings.iCloudSyncProfiles || settings.iCloudSyncOverrides
                for category in SyncCategory.allCases {
                    category.setEnabled(false, on: &settings)
                }
                settings.iCloudSyncProfiles = false
                settings.iCloudSyncOverrides = false
                changed = true
            }
        }
        if changed {
            applyRemote(settings)
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPulled"))
        }
        if zoneSyncSilencedByDeletion {
            // The remote store was wiped: the sync zone is gone too, so the
            // engine's merge base (tagged with the deleted zone's generation)
            // must go with it. Otherwise a later re-enable reads a stale base
            // against a fresh zone and the engine keeps silencing itself.
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.remoteWipe"))
            Task { await ProfileSyncEngine.shared.remoteDataWasDeleted() }
        }
    }

    /// Pulls preference values for enabled categories whose keys exist
    /// remotely. With `reseedMissing`, also publishes local values for keys
    /// the remote store has never seen — reserved for explicit user action so
    /// a deleted store is not silently refilled.
    private func pullPreferences(reseedMissing: Bool) {
        guard let settingsStore else { return }
        var settings = settingsStore.settings
        var changed = false
        for key in Self.syncedPreferences where key.category.isEnabled(settings) {
            if key.importValue(&settings, keyValueStore) {
                changed = true
            }
        }
        if changed {
            applyRemote(settings)
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.settingsPulled"))
        }
        if reseedMissing {
            pushMissingPreferences(settingsStore.settings)
        }
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let settingsStore, settingsStore.settings.iCloudSyncEnabled,
              let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange,
             NSUbiquitousKeyValueStoreAccountChange:
            break
        default:
            // Quota violations carry no usable values; surface them instead.
            SyncStatusStore.shared.record(String(localized: "icloudSync.status.quotaExceeded"), isError: true)
            return
        }

        let configurationKeys = Set(SyncCategory.allCases.map(\.configKey) + [KVSKey.configProfiles, KVSKey.configOverrides])
        let remoteHasConfiguration = configurationKeys.contains { keyValueStore.object(forKey: $0) != nil }
        if reason == NSUbiquitousKeyValueStoreInitialSyncChange, didPushFromUserAction,
           !remoteHasConfiguration {
            // Writes made before the first iCloud download are discarded, so
            // re-publish this session's user choices now that the store works.
            pushConfiguration(settingsStore.settings)
            pushMissingPreferences(settingsStore.settings)
        }

        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        if changedKeys.contains(where: configurationKeys.contains) {
            pullConfiguration(remoteDeletionSilencesLocal: true)
            // A configuration change may have switched categories on: import
            // every enabled category wholesale. Imports are idempotent and
            // reseeding is left to the initiating device.
            pullPreferences(reseedMissing: false)
            return
        }

        let settings = settingsStore.settings
        let changedPreferences = Self.syncedPreferences.filter {
            $0.category.isEnabled(settings) && changedKeys.contains($0.kvsKey)
        }
        guard !changedPreferences.isEmpty else { return }

        var updated = settings
        var changed = false
        for key in changedPreferences {
            if key.importValue(&updated, keyValueStore) {
                changed = true
            }
        }
        if changed {
            applyRemote(updated)
        }
    }

    private func applyRemote(_ settings: Settings) {
        guard let settingsStore else { return }
        isApplyingRemoteChanges = true
        settingsStore.settings = settings
        isApplyingRemoteChanges = false
        // Remote applies skip settingsDidChange (echo guard), so notify the
        // profile engine about configuration changes explicitly.
        notifyProfileSyncEngine()
    }

    /// Turns the profile-zone content switches (profiles and global
    /// overrides) off WITHOUT publishing the change to KVS. Used by the
    /// profile sync engine when the remote sync zone was deleted elsewhere:
    /// pushing here would resurrect the deleted configuration on every peer.
    func silenceZoneSyncFromRemote() {
        guard isStarted, let settingsStore,
              settingsStore.settings.iCloudSyncProfiles || settingsStore.settings.iCloudSyncOverrides else { return }
        var settings = settingsStore.settings
        settings.iCloudSyncProfiles = false
        settings.iCloudSyncOverrides = false
        applyRemote(settings)
    }

    private func notifyProfileSyncEngine() {
        Task { await ProfileSyncEngine.shared.configurationDidChange() }
    }

    private func remoteBool(forKey key: String) -> Bool? {
        guard keyValueStore.object(forKey: key) != nil else { return nil }
        return keyValueStore.bool(forKey: key)
    }
}

private extension SettingsSyncController.SyncedPreferenceKey {
    typealias Category = SettingsSyncController.SyncCategory

    static func bool(_ category: Category, _ name: String, _ keyPath: WritableKeyPath<Settings, Bool>) -> Self {
        let kvsKey = "settings.\(name)"
        return Self(
            category: category,
            kvsKey: kvsKey,
            export: { $0[keyPath: keyPath] },
            isUnchanged: { $0[keyPath: keyPath] == $1[keyPath: keyPath] },
            importValue: { settings, store in
                guard store.object(forKey: kvsKey) != nil else { return false }
                let value = store.bool(forKey: kvsKey)
                guard settings[keyPath: keyPath] != value else { return false }
                settings[keyPath: keyPath] = value
                return true
            }
        )
    }

    static func int(
        _ category: Category,
        _ name: String,
        _ keyPath: WritableKeyPath<Settings, Int>,
        range: ClosedRange<Int>
    ) -> Self {
        let kvsKey = "settings.\(name)"
        return Self(
            category: category,
            kvsKey: kvsKey,
            export: { $0[keyPath: keyPath] },
            isUnchanged: { $0[keyPath: keyPath] == $1[keyPath: keyPath] },
            importValue: { settings, store in
                guard store.object(forKey: kvsKey) != nil else { return false }
                let value = min(range.upperBound, max(range.lowerBound, Int(store.longLong(forKey: kvsKey))))
                guard settings[keyPath: keyPath] != value else { return false }
                settings[keyPath: keyPath] = value
                return true
            }
        )
    }

    static func string(_ category: Category, _ name: String, _ keyPath: WritableKeyPath<Settings, String>) -> Self {
        let kvsKey = "settings.\(name)"
        return Self(
            category: category,
            kvsKey: kvsKey,
            export: { $0[keyPath: keyPath] },
            isUnchanged: { $0[keyPath: keyPath] == $1[keyPath: keyPath] },
            importValue: { settings, store in
                guard let value = store.object(forKey: kvsKey) as? String,
                      settings[keyPath: keyPath] != value else { return false }
                settings[keyPath: keyPath] = value
                return true
            }
        )
    }

    static func stringEnum<Value: RawRepresentable & Equatable>(
        _ category: Category,
        _ name: String,
        _ keyPath: WritableKeyPath<Settings, Value>
    ) -> Self where Value.RawValue == String {
        let kvsKey = "settings.\(name)"
        return Self(
            category: category,
            kvsKey: kvsKey,
            export: { $0[keyPath: keyPath].rawValue },
            isUnchanged: { $0[keyPath: keyPath] == $1[keyPath: keyPath] },
            importValue: { settings, store in
                guard let rawValue = store.object(forKey: kvsKey) as? String,
                      let value = Value(rawValue: rawValue),
                      settings[keyPath: keyPath] != value else { return false }
                settings[keyPath: keyPath] = value
                return true
            }
        )
    }
}
