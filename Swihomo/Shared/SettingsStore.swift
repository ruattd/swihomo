import Combine
import Darwin
import Foundation
import SwiftUI
import os.log

struct Settings: Codable, Equatable, @unchecked Sendable {
    var appTheme: AppTheme = .system
    var appLanguage: AppLanguage = .system
    var showsMenuBar: Bool = true
    var hidesDockIcon: Bool = false
    var menuBarDisplay: MenuBarDisplay = .iconAndSpeed
    var connectionSortCriterion: ConnectionSortCriterion = .process
    var connectionSortDirection: ProxySortDirection = .ascending
    var subscriptionInfoDisplay: SubscriptionInfoDisplay = .used
    var automaticallyReclaimsMemory: Bool = false
    var replaceGeoDatabasesWithRulesets: Bool = false
    var realtimeDelayTest: Bool = false
    var delayTestMaxConcurrency: Int = 4
    var autoCollapseProxyGroups: Bool = false
    var appLogLevel: LogLevel = .info
    var packetTunnelBypassesPrivateNetworks: Bool = false
    var packetTunnelBypassAPNs: Bool = false
    var packetTunnelExcludeCellularServices: Bool = true
    var packetTunnelIncludeAllNetworks: Bool = false
    var packetTunnelBypassCIDRs: String = ""
    var packetTunnelMTU: Int = PacketTunnelMTULimits.defaultValue
    var packetTunnelCustomDNSServers: String = ""
    var packetTunnelIPv6Enabled: Bool = true
    var packetTunnelUseMipstack: Bool = false
    var proxyGroupSortCriterion: ProxyGroupSortCriterion = .original
    var proxyGroupSortDirection: ProxySortDirection = .ascending
    var proxyNodeSortCriterion: ProxyNodeSortCriterion = .original
    var proxyNodeSortDirection: ProxySortDirection = .ascending
    var pendingCoreLogClear: Bool = false
    /// Geo-data timestamps keyed by ExternalResource.id (a string, not a UUID).
    var geoDataLastUpdated: [String: Date] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case appTheme
        case appLanguage
        case showsMenuBar
        case hidesDockIcon
        case menuBarDisplay
        case connectionSortCriterion
        case connectionSortDirection
        case subscriptionInfoDisplay
        case automaticallyReclaimsMemory
        case replaceGeoDatabasesWithRulesets
        case realtimeDelayTest
        case delayTestMaxConcurrency
        case autoCollapseProxyGroups
        case appLogLevel
        case packetTunnelBypassesPrivateNetworks
        case packetTunnelBypassAPNs
        case packetTunnelExcludeCellularServices
        case packetTunnelIncludeAllNetworks
        case packetTunnelBypassCIDRs
        case packetTunnelMTU
        case packetTunnelCustomDNSServers
        case packetTunnelIPv6Enabled
        case packetTunnelUseMipstack
        case proxyGroupSortCriterion
        case proxyGroupSortDirection
        case proxyNodeSortCriterion
        case proxyNodeSortDirection
        case pendingCoreLogClear
        case geoDataLastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appTheme = try container.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        showsMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBar) ?? true
        hidesDockIcon = try container.decodeIfPresent(Bool.self, forKey: .hidesDockIcon) ?? false
        menuBarDisplay = try container.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay) ?? .iconAndSpeed
        connectionSortCriterion = try container.decodeIfPresent(ConnectionSortCriterion.self, forKey: .connectionSortCriterion) ?? .process
        connectionSortDirection = try container.decodeIfPresent(ProxySortDirection.self, forKey: .connectionSortDirection) ?? .ascending
        subscriptionInfoDisplay = try container.decodeIfPresent(SubscriptionInfoDisplay.self, forKey: .subscriptionInfoDisplay) ?? .used
        automaticallyReclaimsMemory = try container.decodeIfPresent(Bool.self, forKey: .automaticallyReclaimsMemory) ?? false
        replaceGeoDatabasesWithRulesets = try container.decodeIfPresent(Bool.self, forKey: .replaceGeoDatabasesWithRulesets) ?? false
        realtimeDelayTest = try container.decodeIfPresent(Bool.self, forKey: .realtimeDelayTest) ?? false
        delayTestMaxConcurrency = try container.decodeIfPresent(Int.self, forKey: .delayTestMaxConcurrency) ?? 4
        autoCollapseProxyGroups = try container.decodeIfPresent(Bool.self, forKey: .autoCollapseProxyGroups) ?? false
        appLogLevel = try container.decodeIfPresent(LogLevel.self, forKey: .appLogLevel) ?? .info
        packetTunnelBypassesPrivateNetworks = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelBypassesPrivateNetworks) ?? false
        packetTunnelBypassAPNs = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelBypassAPNs) ?? false
        packetTunnelExcludeCellularServices = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelExcludeCellularServices) ?? true
        packetTunnelIncludeAllNetworks = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelIncludeAllNetworks) ?? false
        packetTunnelBypassCIDRs = try container.decodeIfPresent(String.self, forKey: .packetTunnelBypassCIDRs) ?? ""
        packetTunnelMTU = try container.decodeIfPresent(Int.self, forKey: .packetTunnelMTU) ?? PacketTunnelMTULimits.defaultValue
        packetTunnelCustomDNSServers = try container.decodeIfPresent(String.self, forKey: .packetTunnelCustomDNSServers) ?? ""
        packetTunnelIPv6Enabled = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelIPv6Enabled) ?? true
        packetTunnelUseMipstack = try container.decodeIfPresent(Bool.self, forKey: .packetTunnelUseMipstack) ?? false
        proxyGroupSortCriterion = try container.decodeIfPresent(ProxyGroupSortCriterion.self, forKey: .proxyGroupSortCriterion) ?? .original
        proxyGroupSortDirection = try container.decodeIfPresent(ProxySortDirection.self, forKey: .proxyGroupSortDirection) ?? .ascending
        proxyNodeSortCriterion = try container.decodeIfPresent(ProxyNodeSortCriterion.self, forKey: .proxyNodeSortCriterion) ?? .original
        proxyNodeSortDirection = try container.decodeIfPresent(ProxySortDirection.self, forKey: .proxyNodeSortDirection) ?? .ascending
        pendingCoreLogClear = try container.decodeIfPresent(Bool.self, forKey: .pendingCoreLogClear) ?? false
        geoDataLastUpdated = try container.decodeIfPresent([String: Date].self, forKey: .geoDataLastUpdated) ?? [:]
    }
}

#if os(macOS)
extension MenuBarDisplay: Codable {}
extension MenuBarDisplay: Hashable {}
#else
enum MenuBarDisplay: String, CaseIterable, Identifiable, Codable, Hashable {
    case icon
    case speed
    case iconAndSpeed

    var id: String { rawValue }
}
#endif

extension AppTheme: Codable {}
extension AppLanguage: Codable {}
extension ConnectionSortCriterion: Codable {}
extension ProxySortDirection: Codable {}
extension SubscriptionInfoDisplay: Codable {}
extension ProxyGroupSortCriterion: Codable {}
extension ProxyNodeSortCriterion: Codable {}

extension AppTheme: Hashable {}
extension AppLanguage: Hashable {}
extension ConnectionSortCriterion: Hashable {}
extension ProxySortDirection: Hashable {}
extension SubscriptionInfoDisplay: Hashable {}
extension ProxyGroupSortCriterion: Hashable {}
extension ProxyNodeSortCriterion: Hashable {}
extension LogLevel: Hashable {}

private let settingsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.swihomo.client",
    category: "SettingsStore"
)

private final class SettingsPersistence: @unchecked Sendable {
    struct LoadResult {
        let settings: Settings
        let shouldPersist: Bool
    }

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let settingsURL: URL
    private let backupURL: URL
    private let lockURL: URL
    private let lockDescriptor: Int32
    let isStorageReadOnly: Bool

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.settingsURL = directoryURL.appendingPathComponent("settings.json")
        self.backupURL = directoryURL.appendingPathComponent("settings.json.bak")
        self.lockURL = directoryURL.appendingPathComponent("settings.lock")

        var descriptor: Int32 = -1
        var readOnly = false
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            // O_EXLOCK | O_NONBLOCK atomically acquires a non-blocking exclusive
            // flock(2) lock at open time; closing the descriptor releases it.
            descriptor = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_EXLOCK | O_NONBLOCK, mode_t(0o600))
            if descriptor < 0 {
                let openError = errno
                readOnly = true
                if openError == EAGAIN {
                    settingsLogger.error("Settings storage is locked by another instance; running read-only.")
                } else {
                    settingsLogger.error("Unable to open settings lock (errno \(openError, privacy: .public)).")
                }
            } else {
                _ = Darwin.chmod(directoryURL.path, mode_t(0o700))
                _ = Darwin.chmod(lockURL.path, mode_t(0o600))
            }
        } catch {
            readOnly = true
            settingsLogger.error("Unable to prepare settings storage: \(error.localizedDescription, privacy: .public)")
        }

        self.lockDescriptor = descriptor
        self.isStorageReadOnly = readOnly
    }

    deinit {
        guard lockDescriptor >= 0 else { return }
        // Closing the descriptor releases the exclusive lock acquired via O_EXLOCK.
        _ = Darwin.close(lockDescriptor)
    }

    func load() -> LoadResult {
        if var settings = decodeSettings(at: settingsURL) {
            let didMergeResiduals = mergeLegacyResiduals(into: &settings)
            return LoadResult(settings: settings, shouldPersist: didMergeResiduals)
        }
        if var settings = decodeSettings(at: backupURL) {
            _ = mergeLegacyResiduals(into: &settings)
            settingsLogger.notice("Recovered settings from the backup file.")
            return LoadResult(settings: settings, shouldPersist: true)
        }

        let migration = migrateLegacySettings()
        if migration.didFindLegacyValues {
            settingsLogger.notice("Migrated settings from legacy UserDefaults.")
            return LoadResult(settings: migration.settings, shouldPersist: true)
        }

        settingsLogger.notice("No readable settings file or legacy values were found; using built-in defaults.")
        return LoadResult(settings: Settings(), shouldPersist: false)
    }

    func persist(_ settings: Settings) {
        guard !isStorageReadOnly else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(settings)
            try atomicWrite(data, to: settingsURL)
            try atomicWrite(data, to: backupURL)
        } catch {
            settingsLogger.error("Unable to persist settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func decodeSettings(at url: URL) -> Settings? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Settings.self, from: data)
        } catch {
            settingsLogger.error("Unable to decode settings file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            preserveCorruptFile(at: url)
            return nil
        }
    }

    private func preserveCorruptFile(at url: URL) {
        guard !isStorageReadOnly else {
            settingsLogger.notice("Leaving corrupt settings file in place because storage is read-only.")
            return
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        var destination = directoryURL.appendingPathComponent("settings.corrupt-\(timestamp).json")
        if fileManager.fileExists(atPath: destination.path) {
            destination = directoryURL.appendingPathComponent("settings.corrupt-\(timestamp)-\(UUID().uuidString).json")
        }

        do {
            try fileManager.moveItem(at: url, to: destination)
            _ = Darwin.chmod(destination.path, mode_t(0o600))
            settingsLogger.notice("Preserved corrupt settings file as \(destination.lastPathComponent, privacy: .public).")
        } catch {
            settingsLogger.error("Unable to preserve corrupt settings file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func migrateLegacySettings() -> (settings: Settings, didFindLegacyValues: Bool) {
        let defaults = UserDefaults.standard
        var settings = Settings()
        var didFindLegacyValues = false

        func hasValue(_ key: String) -> Bool {
            defaults.object(forKey: key) != nil
        }

        func stringValue(_ key: String) -> String? {
            guard let value = defaults.object(forKey: key) else { return nil }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }

        func boolValue(_ key: String) -> Bool? {
            guard let value = defaults.object(forKey: key) else { return nil }
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            guard let string = value as? String else { return nil }
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }

        func intValue(_ key: String) -> Int? {
            guard let value = defaults.object(forKey: key) else { return nil }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return nil
        }

        func applyString<T: RawRepresentable>(
            _ key: String,
            to keyPath: WritableKeyPath<Settings, T>
        ) where T.RawValue == String {
            guard hasValue(key) else { return }
            didFindLegacyValues = true
            if let rawValue = stringValue(key), let value = T(rawValue: rawValue) {
                settings[keyPath: keyPath] = value
            }
        }

        func applyBool(_ key: String, to keyPath: WritableKeyPath<Settings, Bool>) {
            guard hasValue(key) else { return }
            didFindLegacyValues = true
            if let value = boolValue(key) {
                settings[keyPath: keyPath] = value
            }
        }

        func applyInt(_ key: String, to keyPath: WritableKeyPath<Settings, Int>) {
            guard hasValue(key) else { return }
            didFindLegacyValues = true
            if let value = intValue(key) {
                settings[keyPath: keyPath] = value
            }
        }

        applyString("appTheme", to: \Settings.appTheme)
        applyString("appLanguage", to: \Settings.appLanguage)
        applyBool("showsMenuBar", to: \Settings.showsMenuBar)
        applyBool("hidesDockIcon", to: \Settings.hidesDockIcon)
        applyString("menuBarDisplay", to: \Settings.menuBarDisplay)
        applyString("connectionSortCriterion", to: \Settings.connectionSortCriterion)
        applyString("connectionSortDirection", to: \Settings.connectionSortDirection)
        applyString("subscriptionInfoDisplay", to: \Settings.subscriptionInfoDisplay)
        applyBool("automaticallyReclaimsMemory", to: \Settings.automaticallyReclaimsMemory)
        applyBool("replaceGeoDatabasesWithRulesets", to: \Settings.replaceGeoDatabasesWithRulesets)
        applyBool("realtimeDelayTest", to: \Settings.realtimeDelayTest)
        applyInt("delayTestMaxConcurrency", to: \Settings.delayTestMaxConcurrency)
        applyBool("autoCollapseProxyGroups", to: \Settings.autoCollapseProxyGroups)
        applyString("appLogLevel", to: \Settings.appLogLevel)
        applyBool("packetTunnelBypassesPrivateNetworks", to: \Settings.packetTunnelBypassesPrivateNetworks)
        applyBool("packetTunnelBypassAPNs", to: \Settings.packetTunnelBypassAPNs)
        applyBool("packetTunnelExcludeCellularServices", to: \Settings.packetTunnelExcludeCellularServices)
        applyBool("packetTunnelIncludeAllNetworks", to: \Settings.packetTunnelIncludeAllNetworks)

        if hasValue("packetTunnelBypassCIDRs") {
            didFindLegacyValues = true
            if let value = stringValue("packetTunnelBypassCIDRs") {
                settings.packetTunnelBypassCIDRs = value
            }
        }
        applyInt("packetTunnelMTU", to: \Settings.packetTunnelMTU)
        if hasValue("packetTunnelCustomDNSServers") {
            didFindLegacyValues = true
            if let value = stringValue("packetTunnelCustomDNSServers") {
                settings.packetTunnelCustomDNSServers = value
            }
        }
        applyBool("packetTunnelIPv6Enabled", to: \Settings.packetTunnelIPv6Enabled)
        applyBool("packetTunnelUseMipstack", to: \Settings.packetTunnelUseMipstack)
        applyString("proxyGroupSortCriterion", to: \Settings.proxyGroupSortCriterion)
        applyString("proxyGroupSortDirection", to: \Settings.proxyGroupSortDirection)
        applyString("proxyNodeSortCriterion", to: \Settings.proxyNodeSortCriterion)
        applyString("proxyNodeSortDirection", to: \Settings.proxyNodeSortDirection)
        applyBool("logs.pendingCoreLogClear", to: \Settings.pendingCoreLogClear)

        let dateFormatter = ISO8601DateFormatter()
        let prefix = "com.swihomo.geodata.lastUpdated."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            didFindLegacyValues = true
            let id = String(key.dropFirst(prefix.count))
            guard !id.isEmpty, let date = legacyDate(value, formatter: dateFormatter) else { continue }
            settings.geoDataLastUpdated[id] = date
        }

        return (settings, didFindLegacyValues)
    }

    private func legacyDate(_ value: Any, formatter: ISO8601DateFormatter) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        if let string = value as? String {
            if let date = formatter.date(from: string) { return date }
            if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        }
        return nil
    }

    /// Pre-refactor builds stored geo-data timestamps and the deferred core-log flag
    /// under keys the first migration pass did not know. Merge any survivors into the
    /// loaded settings so upgrading never loses them; idempotent after the first persist.
    private func mergeLegacyResiduals(into settings: inout Settings) -> Bool {
        let defaults = UserDefaults.standard
        var didMerge = false
        let prefix = "com.swihomo.geodata.lastUpdated."
        let formatter = ISO8601DateFormatter()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let id = String(key.dropFirst(prefix.count))
            guard !id.isEmpty, let date = legacyDate(value, formatter: formatter) else { continue }
            if let existing = settings.geoDataLastUpdated[id], existing >= date { continue }
            settings.geoDataLastUpdated[id] = date
            didMerge = true
        }
        if !settings.pendingCoreLogClear, defaults.bool(forKey: "logs.pendingCoreLogClear") {
            settings.pendingCoreLogClear = true
            didMerge = true
        }
        return didMerge
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = directoryURL.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporary) }

        try data.write(to: temporary)
        guard Darwin.chmod(temporary.path, mode_t(0o600)) == 0 else {
            throw posixError(errno, path: temporary.path)
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw posixError(errno, path: destination.path)
        }
    }

    private func posixError(_ code: Int32, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // Manual publisher + equality gate: SwiftUI writes scene bindings (e.g.
    // MenuBarExtra isInserted) back during graph updates even when the value is
    // unchanged. Re-emitting objectWillChange for such no-op writes re-invalidates
    // every observer and loops AttributeGraph forever, so only real changes publish
    // and persist.
    let objectWillChange = ObservableObjectPublisher()

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            objectWillChange.send()
            guard let persistence, !persistence.isStorageReadOnly else { return }
            let snapshot = settings
            persistenceQueue.async {
                persistence.persist(snapshot)
            }
        }
    }

    private(set) var isStorageReadOnly: Bool
    private let persistence: SettingsPersistence?
    private let persistenceQueue = DispatchQueue(label: "com.swihomo.settings.persistence")

    private init() {
        if ScreenshotDemoMode.isEnabled {
            // Screenshot demo mode is memory-only: fixed defaults with no disk,
            // no lock, and no migration. Writes still update the UI through
            // objectWillChange but are never persisted.
            persistence = nil
            isStorageReadOnly = true
            settings = Settings()
            return
        }

        let persistence = SettingsPersistence(directoryURL: Self.storageDirectoryURL)
        let loadResult = persistence.load()
        self.persistence = persistence
        self.isStorageReadOnly = persistence.isStorageReadOnly
        self.settings = loadResult.settings
        if loadResult.shouldPersist && !persistence.isStorageReadOnly {
            persistence.persist(loadResult.settings)
        }
    }

    func binding<V>(_ keyPath: WritableKeyPath<Settings, V>) -> Binding<V> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    private static var storageDirectoryURL: URL {
        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupport.appendingPathComponent("Swihomo", isDirectory: true)
        }

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Swihomo", isDirectory: true)
    }
}

@MainActor
@propertyWrapper
struct AppSetting<Value>: DynamicProperty {
    @ObservedObject private var store: SettingsStore
    private let keyPath: WritableKeyPath<Settings, Value>

    init(_ keyPath: WritableKeyPath<Settings, Value>) {
        self.keyPath = keyPath
        self._store = ObservedObject(wrappedValue: SettingsStore.shared)
    }

    var wrappedValue: Value {
        get { store.settings[keyPath: keyPath] }
        nonmutating set { store.settings[keyPath: keyPath] = newValue }
    }

    var projectedValue: Binding<Value> {
        store.binding(keyPath)
    }
}
