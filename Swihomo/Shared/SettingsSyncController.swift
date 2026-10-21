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
/// - Preference values (`settings.*`) only sync while the preferences content
///   switch is on. Turning a switch off never deletes remote data.
/// - KVS resolves conflicts last-writer-wins per key server-side, so inbound
///   values are simply applied; no local merge is needed.
@MainActor
final class SettingsSyncController {
    static let shared = SettingsSyncController()

    private enum KVSKey {
        static let configPreferences = "sync.config.preferences"
        static let configProfiles = "sync.config.profiles"
    }

    /// One syncable preference entry: how to export it, how to import it, and
    /// how to tell whether it changed between two settings snapshots.
    fileprivate struct SyncedPreferenceKey {
        let kvsKey: String
        let export: (Settings) -> Any
        let isUnchanged: (Settings, Settings) -> Bool
        /// Applies the remote value into `settings` when the key exists.
        /// Returns true when the local value changed.
        let importValue: (inout Settings, NSUbiquitousKeyValueStore) -> Bool
    }

    private static let syncedPreferences: [SyncedPreferenceKey] = [
        .stringEnum("appTheme", \.appTheme),
        .stringEnum("appLanguage", \.appLanguage),
        .stringEnum("menuBarDisplay", \.menuBarDisplay),
        .stringEnum("connectionSortCriterion", \.connectionSortCriterion),
        .stringEnum("connectionSortDirection", \.connectionSortDirection),
        .stringEnum("subscriptionInfoDisplay", \.subscriptionInfoDisplay),
        .bool("realtimeDelayTest", \.realtimeDelayTest),
        .int("delayTestMaxConcurrency", \.delayTestMaxConcurrency, range: 1...32),
        .bool("autoCollapseProxyGroups", \.autoCollapseProxyGroups),
        .stringEnum("appLogLevel", \.appLogLevel),
        .bool("replaceGeoDatabasesWithRulesets", \.replaceGeoDatabasesWithRulesets),
        .bool("automaticallyReclaimsMemory", \.automaticallyReclaimsMemory),
        .stringEnum("proxyGroupSortCriterion", \.proxyGroupSortCriterion),
        .stringEnum("proxyGroupSortDirection", \.proxyGroupSortDirection),
        .stringEnum("proxyNodeSortCriterion", \.proxyNodeSortCriterion),
        .stringEnum("proxyNodeSortDirection", \.proxyNodeSortDirection),
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
        keyValueStore.removeObject(forKey: KVSKey.configPreferences)
        keyValueStore.removeObject(forKey: KVSKey.configProfiles)
        for key in Self.syncedPreferences {
            keyValueStore.removeObject(forKey: key.kvsKey)
        }
        keyValueStore.synchronize()
        var settings = settingsStore.settings
        settings.iCloudSyncPreferences = false
        settings.iCloudSyncProfiles = false
        applyRemote(settings)
        logger.notice("Deleted all settings data from the ubiquitous key-value store.")
    }

    // MARK: - Outbound

    /// Called from `SettingsStore.settings.didSet` after the equality gate, so
    /// only real changes arrive here.
    func settingsDidChange(new: Settings, old: Settings) {
        guard isStarted, !isApplyingRemoteChanges else { return }

        if new.iCloudSyncEnabled, !old.iCloudSyncEnabled {
            // Master switch just turned on: pull the sync configuration first
            // (another device may already have chosen content categories), and
            // silence local categories if the remote store was wiped.
            keyValueStore.synchronize()
            pullConfiguration(remoteDeletionSilencesLocal: true)
            if let settingsStore {
                // Publish only configuration keys the remote store lacks, and
                // never overwrite existing remote values from a possibly
                // stale local cache.
                let settings = settingsStore.settings
                var didPush = false
                if remoteBool(forKey: KVSKey.configPreferences) == nil {
                    keyValueStore.set(settings.iCloudSyncPreferences, forKey: KVSKey.configPreferences)
                    didPush = true
                }
                if remoteBool(forKey: KVSKey.configProfiles) == nil {
                    keyValueStore.set(settings.iCloudSyncProfiles, forKey: KVSKey.configProfiles)
                    didPush = true
                }
                if didPush {
                    keyValueStore.synchronize()
                    didPushFromUserAction = true
                }
                if settings.iCloudSyncPreferences {
                    pullPreferences(reseedMissing: true)
                }
            }
            return
        }

        guard new.iCloudSyncEnabled else { return }

        if new.iCloudSyncPreferences != old.iCloudSyncPreferences
            || new.iCloudSyncProfiles != old.iCloudSyncProfiles {
            pushConfiguration(new)
            didPushFromUserAction = true
        }

        if new.iCloudSyncPreferences {
            if !old.iCloudSyncPreferences {
                pullPreferences(reseedMissing: true)
                didPushFromUserAction = true
            } else {
                pushChangedPreferences(new: new, old: old)
            }
        }
    }

    private func pushConfiguration(_ settings: Settings) {
        keyValueStore.set(settings.iCloudSyncPreferences, forKey: KVSKey.configPreferences)
        keyValueStore.set(settings.iCloudSyncProfiles, forKey: KVSKey.configProfiles)
        keyValueStore.synchronize()
        didPushFromUserAction = true
    }

    private func pushChangedPreferences(new: Settings, old: Settings) {
        var didPush = false
        for key in Self.syncedPreferences where !key.isUnchanged(new, old) {
            keyValueStore.set(key.export(new), forKey: key.kvsKey)
            didPush = true
        }
        if didPush {
            keyValueStore.synchronize()
            didPushFromUserAction = true
        }
    }

    /// Publishes local values for keys the remote store has never seen, so
    /// enabling sync on a fresh account still uploads this device's setup.
    private func pushMissingPreferences(_ settings: Settings) {
        var didPush = false
        for key in Self.syncedPreferences where keyValueStore.object(forKey: key.kvsKey) == nil {
            keyValueStore.set(key.export(settings), forKey: key.kvsKey)
            didPush = true
        }
        if didPush {
            keyValueStore.synchronize()
            didPushFromUserAction = true
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
        if settingsStore.settings.iCloudSyncPreferences {
            pullPreferences(reseedMissing: false)
        }
    }

    /// Applies the remotely stored sync configuration (content category
    /// switches). Never pushes: outbound configuration writes happen only for
    /// local user actions, so a deleted store stays deleted.
    private func pullConfiguration(remoteDeletionSilencesLocal: Bool = false) {
        guard let settingsStore else { return }
        var settings = settingsStore.settings
        var changed = false
        let remotePreferences = remoteBool(forKey: KVSKey.configPreferences)
        let remoteProfiles = remoteBool(forKey: KVSKey.configProfiles)
        if let value = remotePreferences, settings.iCloudSyncPreferences != value {
            settings.iCloudSyncPreferences = value
            changed = true
        }
        if let value = remoteProfiles, settings.iCloudSyncProfiles != value {
            settings.iCloudSyncProfiles = value
            changed = true
        }
        if remoteDeletionSilencesLocal, remotePreferences == nil, remoteProfiles == nil,
           settings.iCloudSyncPreferences || settings.iCloudSyncProfiles {
            settings.iCloudSyncPreferences = false
            settings.iCloudSyncProfiles = false
            changed = true
        }
        if changed {
            applyRemote(settings)
        }
    }

    /// Pulls preference values for keys present remotely. With
    /// `reseedMissing`, also publishes local values for keys the remote store
    /// has never seen — reserved for explicit user action so a deleted store
    /// is not silently refilled.
    private func pullPreferences(reseedMissing: Bool) {
        guard let settingsStore else { return }
        var settings = settingsStore.settings
        var changed = false
        for key in Self.syncedPreferences {
            if key.importValue(&settings, keyValueStore) {
                changed = true
            }
        }
        if changed {
            applyRemote(settings)
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
            // Quota violations carry no usable values; ignore them.
            return
        }
        if reason == NSUbiquitousKeyValueStoreInitialSyncChange, didPushFromUserAction,
           remoteBool(forKey: KVSKey.configPreferences) == nil,
           remoteBool(forKey: KVSKey.configProfiles) == nil {
            // Writes made before the first iCloud download are discarded, so
            // re-publish this session's user choices now that the store works.
            pushConfiguration(settingsStore.settings)
            if settingsStore.settings.iCloudSyncPreferences {
                pushMissingPreferences(settingsStore.settings)
            }
        }

        guard let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        let configurationChanged = changedKeys.contains(KVSKey.configPreferences)
            || changedKeys.contains(KVSKey.configProfiles)
        if configurationChanged {
            let preferencesWereEnabled = settingsStore.settings.iCloudSyncPreferences
            pullConfiguration(remoteDeletionSilencesLocal: true)
            guard settingsStore.settings.iCloudSyncPreferences else { return }
            guard preferencesWereEnabled else {
                // The preferences category was just switched on remotely:
                // import everything, not only the keys in this notification.
                // Reseeding is left to the initiating device.
                pullPreferences(reseedMissing: false)
                return
            }
        } else {
            guard settingsStore.settings.iCloudSyncPreferences else { return }
        }

        let settings = settingsStore.settings
        let changedPreferences = Self.syncedPreferences.filter { changedKeys.contains($0.kvsKey) }
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
    }

    private func remoteBool(forKey key: String) -> Bool? {
        guard keyValueStore.object(forKey: key) != nil else { return nil }
        return keyValueStore.bool(forKey: key)
    }
}

private extension SettingsSyncController.SyncedPreferenceKey {
    static func bool(_ name: String, _ keyPath: WritableKeyPath<Settings, Bool>) -> Self {
        let kvsKey = "settings.\(name)"
        return Self(
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

    static func int(_ name: String, _ keyPath: WritableKeyPath<Settings, Int>, range: ClosedRange<Int>) -> Self {
        let kvsKey = "settings.\(name)"
        return Self(
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

    static func stringEnum<Value: RawRepresentable & Equatable>(
        _ name: String,
        _ keyPath: WritableKeyPath<Settings, Value>
    ) -> Self where Value.RawValue == String {
        let kvsKey = "settings.\(name)"
        return Self(
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
