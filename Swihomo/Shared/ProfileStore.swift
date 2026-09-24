import Foundation
import os.log
import Darwin

actor SharedProfileRepository {
    private let fileManager = FileManager.default
    private let logger: Logger
    private let storageRoot: URL?
    private let profilesRoot: URL?
    private let manifestFile: URL?
    private let backupManifestFile: URL?
    private let lockFile: URL?
    private var lockFileDescriptor: Int32?
    private(set) var isStorageReadOnly = false

    private var snapshot: ClientSnapshot = .empty()
    private var profileContentsByID: [UUID: String] = [:]
    private var profileFileURLs: [UUID: URL] = [:]
    private var pendingInitializationError: Error? = nil

    private struct DownloadedProfile {
        let contents: String
        let subscriptionInfo: MihomoSubscriptionInfo?
    }

    private struct LoadedStorage {
        let snapshot: ClientSnapshot
        let contentsByID: [UUID: String]
        let fileURLsByID: [UUID: URL]
        let rebuilt: Bool
    }

    private enum ProfileStorageError: LocalizedError {
        case readOnly
        case contentsUnavailable

        var errorDescription: String? {
            switch self {
            case .readOnly:
                "Profile storage is read-only because another Swihomo instance owns the storage lock."
            case .contentsUnavailable:
                "The profile contents are unavailable in the in-memory profile store."
            }
        }
    }

    init() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swihomo.client", category: "ProfileStore")
        self.logger = logger

        if ScreenshotDemoMode.isEnabled {
            // Screenshot demo mode serves in-memory fixtures through AppModel and
            // never touches profile storage: leave storage unconfigured and
            // read-only — no directories, no lock, no disk IO.
            self.storageRoot = nil
            self.profilesRoot = nil
            self.manifestFile = nil
            self.backupManifestFile = nil
            self.lockFile = nil
            self.lockFileDescriptor = nil
            self.isStorageReadOnly = true
            return
        }

        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            self.storageRoot = nil
            self.profilesRoot = nil
            self.manifestFile = nil
            self.backupManifestFile = nil
            self.lockFile = nil
            self.lockFileDescriptor = nil
            self.pendingInitializationError = ClientError.storageUnavailable
            return
        }

        let root = applicationSupport.appendingPathComponent("Swihomo", isDirectory: true)
        let profiles = root.appendingPathComponent("Profiles", isDirectory: true)
        self.storageRoot = root
        self.profilesRoot = profiles
        self.manifestFile = root.appendingPathComponent("profiles.json")
        self.backupManifestFile = root.appendingPathComponent("profiles.json.bak")
        self.lockFile = root.appendingPathComponent("profiles.lock")
        self.lockFileDescriptor = nil

        do {
            try ensureDirectory(root)
            try ensureDirectory(profiles)
            acquireStorageLock()
            if !isStorageReadOnly {
                try repairStoragePermissions()
            }
            let loaded = try loadStorage()
            self.snapshot = loaded.snapshot
            self.profileContentsByID = loaded.contentsByID
            self.profileFileURLs = loaded.fileURLsByID
            if loaded.rebuilt, !isStorageReadOnly {
                try save(loaded.snapshot)
            }
        } catch {
            self.pendingInitializationError = error
        }
    }

    deinit {
        if let lockFileDescriptor {
            // Closing the descriptor releases the exclusive lock acquired via O_EXLOCK.
            _ = Darwin.close(lockFileDescriptor)
        }
    }

    func loadSnapshot() throws -> ClientSnapshot {
        try throwPendingInitializationErrorIfNeeded()
        return snapshot
    }

    func createLocalProfile(name: String, contents: String) throws -> ClientSnapshot {
        try createProfile(name: name, source: .local, remoteURL: nil, contents: contents)
    }

    func createRemoteProfile(
        name: String,
        remoteURL: URL,
        customUserAgent: String?
    ) async throws -> ClientSnapshot {
        try ensureWritable()
        let downloadedProfile = try await downloadProfile(at: remoteURL, customUserAgent: customUserAgent)
        return try createProfile(
            name: name,
            source: .remote,
            remoteURL: remoteURL,
            customUserAgent: customUserAgent,
            contents: downloadedProfile.contents,
            subscriptionInfo: downloadedProfile.subscriptionInfo
        )
    }

    func refreshProfile(_ id: UUID) async throws -> ClientSnapshot {
        try ensureWritable()
        guard let profile = snapshot.profiles.first(where: { $0.id == id }),
              let remoteURL = profile.remoteURL else {
            throw ClientError.missingProfile
        }

        let downloadedProfile = try await downloadProfile(
            at: remoteURL,
            customUserAgent: profile.customUserAgent
        )
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }

        let now = Date.now
        profileContentsByID[id] = downloadedProfile.contents
        snapshot.profiles[index].updatedAt = now
        snapshot.profiles[index].lastFetchedAt = now
        snapshot.profiles[index].subscriptionInfo = downloadedProfile.subscriptionInfo
        try writeProfileContents(downloadedProfile.contents, for: id)
        try save(snapshot)
        return snapshot
    }

    func updateRemoteProfile(
        _ id: UUID,
        name: String,
        remoteURL: URL,
        customUserAgent: String?
    ) throws -> ClientSnapshot {
        try ensureWritable()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }),
              snapshot.profiles[index].source == .remote else {
            throw ClientError.missingProfile
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserAgent = customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.profiles[index].name = trimmedName.isEmpty ? remoteURL.host ?? "Online Profile" : trimmedName
        snapshot.profiles[index].remoteURL = remoteURL
        snapshot.profiles[index].customUserAgent = trimmedUserAgent?.isEmpty == false ? trimmedUserAgent : nil
        snapshot.profiles[index].updatedAt = .now
        try save(snapshot)
        return snapshot
    }

    func profileContents(for id: UUID) throws -> String {
        try throwPendingInitializationErrorIfNeeded()
        guard snapshot.profiles.contains(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        guard let contents = profileContentsByID[id] else {
            throw ProfileStorageError.contentsUnavailable
        }
        return contents
    }

    func updateProfileContents(_ contents: String, for id: UUID) throws -> ClientSnapshot {
        try ensureWritable()
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidProfile
        }

        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        profileContentsByID[id] = contents
        snapshot.profiles[index].updatedAt = .now
        try writeProfileContents(contents, for: id)
        try save(snapshot)
        return snapshot
    }

    func setCustomOverridesEnabled(_ isEnabled: Bool, for id: UUID) throws -> ClientSnapshot {
        try ensureWritable()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.profiles[index].customOverridesEnabled = isEnabled
        try save(snapshot)
        return snapshot
    }

    func setCustomOverrideYAML(_ contents: String, for id: UUID) throws -> ClientSnapshot {
        try ensureWritable()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.profiles[index].customOverrideYAML = contents
        try save(snapshot)
        return snapshot
    }

    func deleteProfile(_ id: UUID) throws -> ClientSnapshot {
        try ensureWritable()
        let configuration = try configurationURL(for: id)
        snapshot.profiles.removeAll { $0.id == id }
        if snapshot.activeProfileID == id {
            snapshot.activeProfileID = nil
        }
        profileContentsByID.removeValue(forKey: id)
        profileFileURLs.removeValue(forKey: id)
        try? fileManager.removeItem(at: configuration)
        try save(snapshot)
        return snapshot
    }

    func activateProfile(_ id: UUID) throws -> ClientSnapshot {
        try ensureWritable()
        guard snapshot.profiles.contains(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.activeProfileID = id
        try save(snapshot)
        return snapshot
    }

    func saveOverrides(_ overrides: ProxyOverrides) throws -> ClientSnapshot {
        try ensureWritable()
        snapshot.overrides = overrides
        try save(snapshot)
        return snapshot
    }

    func runtimeConfiguration(for id: UUID) throws -> (profile: Profile, contents: String, overrides: ProxyOverrides) {
        try throwPendingInitializationErrorIfNeeded()
        guard let profile = snapshot.profiles.first(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        guard let contents = profileContentsByID[id] else {
            throw ProfileStorageError.contentsUnavailable
        }
        return (profile, contents, snapshot.overrides)
    }

    private func createProfile(
        name: String,
        source: ProfileSource,
        remoteURL: URL?,
        customUserAgent: String? = nil,
        contents: String,
        subscriptionInfo: MihomoSubscriptionInfo? = nil
    ) throws -> ClientSnapshot {
        try ensureWritable()
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidProfile
        }

        let now = Date.now
        let profile = Profile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Profile" : name,
            source: source,
            remoteURL: remoteURL,
            customUserAgent: customUserAgent,
            createdAt: now,
            updatedAt: now,
            lastFetchedAt: source == .remote ? now : nil,
            subscriptionInfo: subscriptionInfo
        )
        profileContentsByID[profile.id] = contents
        profileFileURLs[profile.id] = try canonicalConfigurationURL(for: profile.id)
        snapshot.profiles.append(profile)
        try writeProfileContents(contents, for: profile.id)
        try save(snapshot)
        return snapshot
    }

    private func downloadProfile(at url: URL, customUserAgent: String? = nil) async throws -> DownloadedProfile {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let userAgent = customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue(userAgent?.isEmpty == false ? userAgent : MihomoCoreVersion.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw ClientError.httpFailure(response.statusCode)
        }
        let contents = try SubscriptionProfileConverter.yaml(from: data)
        let subscriptionInfo = (response as? HTTPURLResponse).flatMap {
            MihomoSubscriptionInfo(subscriptionUserInfo: $0.value(forHTTPHeaderField: "subscription-userinfo"))
        }
        return DownloadedProfile(contents: contents, subscriptionInfo: subscriptionInfo)
    }

    private func ensureWritable() throws {
        try throwPendingInitializationErrorIfNeeded()
        guard !isStorageReadOnly else {
            throw ProfileStorageError.readOnly
        }
    }

    private func throwPendingInitializationErrorIfNeeded() throws {
        guard let error = pendingInitializationError else { return }
        pendingInitializationError = nil
        throw error
    }

    private func acquireStorageLock() {
        guard let lockFile else { return }
        // O_EXLOCK | O_NONBLOCK atomically acquires a non-blocking exclusive
        // flock(2) lock at open time; closing the descriptor releases it.
        let descriptor = lockFile.path.withCString { path in
            Darwin.open(path, O_RDWR | O_CREAT | O_EXLOCK | O_NONBLOCK, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            isStorageReadOnly = true
            let openError = errno
            if openError == EAGAIN {
                logger.error("profiles.lock is held by another instance; profile storage is read-only.")
            } else {
                logger.error("Unable to open profiles.lock (errno \(openError)); profile storage is read-only.")
            }
            return
        }
        _ = Darwin.chmod(lockFile.path, mode_t(0o600))
        lockFileDescriptor = descriptor
    }

    private func loadStorage() throws -> LoadedStorage {
        let primaryExists = manifestFile.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let backupExists = backupManifestFile.map { fileManager.fileExists(atPath: $0.path) } ?? false

        if primaryExists, let manifestFile, let snapshot = try? decodeManifest(at: manifestFile) {
            return try loadProfileContents(for: snapshot, rebuilt: false)
        }
        if backupExists, let backupManifestFile, let snapshot = try? decodeManifest(at: backupManifestFile) {
            return try loadProfileContents(for: snapshot, rebuilt: false)
        }

        if primaryExists || backupExists {
            if !isStorageReadOnly {
                if primaryExists, let manifestFile {
                    archiveCorruptManifest(at: manifestFile, isBackup: false, primaryExists: primaryExists)
                }
                if backupExists, let backupManifestFile {
                    archiveCorruptManifest(at: backupManifestFile, isBackup: true, primaryExists: primaryExists)
                }
            }
            logger.warning("Both profile manifests were undecodable; rebuilding metadata from local YAML files.")
        }

        let rebuilt = try rebuildManifestFromProfiles()
        return LoadedStorage(
            snapshot: rebuilt.snapshot,
            contentsByID: rebuilt.contentsByID,
            fileURLsByID: rebuilt.fileURLsByID,
            rebuilt: primaryExists || backupExists || !rebuilt.snapshot.profiles.isEmpty
        )
    }

    private func decodeManifest(at url: URL) throws -> ClientSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClientSnapshot.self, from: data)
    }

    private func loadProfileContents(for snapshot: ClientSnapshot, rebuilt: Bool) throws -> LoadedStorage {
        var contentsByID: [UUID: String] = [:]
        var fileURLsByID: [UUID: URL] = [:]
        for profile in snapshot.profiles {
            let url = try canonicalConfigurationURL(for: profile.id)
            contentsByID[profile.id] = try String(contentsOf: url, encoding: .utf8)
            fileURLsByID[profile.id] = url
        }
        return LoadedStorage(
            snapshot: snapshot,
            contentsByID: contentsByID,
            fileURLsByID: fileURLsByID,
            rebuilt: rebuilt
        )
    }

    private func rebuildManifestFromProfiles() throws -> LoadedStorage {
        guard let profilesRoot else {
            throw ClientError.storageUnavailable
        }
        let files = try fileManager.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "yaml" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var profiles: [Profile] = []
        var contentsByID: [UUID: String] = [:]
        var fileURLsByID: [UUID: URL] = [:]
        let now = Date.now
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let stem = file.deletingPathExtension().lastPathComponent
            let id = UUID(uuidString: stem) ?? UUID()
            let profile = Profile(
                id: id,
                name: stem,
                source: .local,
                remoteURL: nil,
                customUserAgent: nil,
                createdAt: now,
                updatedAt: now,
                lastFetchedAt: nil,
                subscriptionInfo: nil
            )
            profiles.append(profile)
            contentsByID[id] = contents
            fileURLsByID[id] = file
        }

        // Remote URLs and override metadata are unrecoverable here because the YAML filenames carry only local content.
        let snapshot = ClientSnapshot(
            schemaVersion: 1,
            profiles: profiles,
            activeProfileID: profiles.first?.id,
            overrides: .default()
        )
        return LoadedStorage(
            snapshot: snapshot,
            contentsByID: contentsByID,
            fileURLsByID: fileURLsByID,
            rebuilt: true
        )
    }

    private func archiveCorruptManifest(at url: URL, isBackup: Bool, primaryExists: Bool) {
        let timestamp = Int(Date.now.timeIntervalSince1970 * 1_000)
        let suffix = isBackup && primaryExists ? "-backup" : ""
        var destination = url.deletingLastPathComponent()
            .appendingPathComponent("profiles.corrupt-\(timestamp)\(suffix).json")
        while fileManager.fileExists(atPath: destination.path) {
            destination = url.deletingLastPathComponent()
                .appendingPathComponent("profiles.corrupt-\(timestamp)-\(UUID().uuidString)\(suffix).json")
        }
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            logger.error("Unable to preserve corrupt profile manifest at \(url.lastPathComponent, privacy: .public).")
        }
    }

    private func repairStoragePermissions() throws {
        if let storageRoot {
            try setPermissions(storageRoot, to: 0o700)
        }
        if let profilesRoot {
            try setPermissions(profilesRoot, to: 0o700)
            let files = try fileManager.contentsOfDirectory(
                at: profilesRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension.lowercased() == "yaml" {
                try setPermissions(file, to: 0o600)
            }
        }
        if let manifestFile, fileManager.fileExists(atPath: manifestFile.path) {
            try setPermissions(manifestFile, to: 0o600)
        }
        if let backupManifestFile, fileManager.fileExists(atPath: backupManifestFile.path) {
            try setPermissions(backupManifestFile, to: 0o600)
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try setPermissions(url, to: 0o700)
    }

    private func setPermissions(_ url: URL, to permissions: Int) throws {
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func manifestURL() throws -> URL {
        guard let manifestFile else { throw ClientError.storageUnavailable }
        return manifestFile
    }

    private func backupManifestURL() throws -> URL {
        guard let backupManifestFile else { throw ClientError.storageUnavailable }
        return backupManifestFile
    }

    private func configurationURL(for id: UUID) throws -> URL {
        if let url = profileFileURLs[id] {
            return url
        }
        return try canonicalConfigurationURL(for: id)
    }

    private func canonicalConfigurationURL(for id: UUID) throws -> URL {
        guard let profilesRoot else { throw ClientError.storageUnavailable }
        return profilesRoot.appendingPathComponent("\(id.uuidString).yaml")
    }

    private func writeProfileContents(_ contents: String, for id: UUID) throws {
        let directory = try profilesDirectory()
        try ensureDirectory(directory)
        let url = try configurationURL(for: id)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try setPermissions(url, to: 0o600)
    }

    private func save(_ snapshot: ClientSnapshot) throws {
        let root = try storageDirectory()
        let profiles = try profilesDirectory()
        try ensureDirectory(root)
        try ensureDirectory(profiles)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let manifest = try manifestURL()
        try atomicWrite(data, to: manifest)
        let backup = try backupManifestURL()
        try atomicWrite(data, to: backup)
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary)
        guard Darwin.chmod(temporary.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: temporary.path])
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    private func storageDirectory() throws -> URL {
        guard let storageRoot else { throw ClientError.storageUnavailable }
        return storageRoot
    }

    private func profilesDirectory() throws -> URL {
        guard let profilesRoot else { throw ClientError.storageUnavailable }
        return profilesRoot
    }
}

private enum SubscriptionProfileConverter {
    static func yaml(from data: Data) throws -> String {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw ClientError.invalidSubscriptionResponse
        }
        return try yaml(from: contents, allowsBase64: true)
    }

    private static func yaml(from rawContents: String, allowsBase64: Bool) throws -> String {
        let contents = rawContents
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else {
            throw ClientError.invalidSubscriptionResponse
        }

        if let jsonYAML = yamlFromJSON(contents) {
            return jsonYAML
        }
        if isYAMLConfiguration(contents) {
            return contents
        }
        if let proxyYAML = try yamlFromProxyLinks(contents) {
            return proxyYAML
        }
        if allowsBase64, let decodedContents = decodedBase64Contents(from: contents) {
            return try yaml(from: decodedContents, allowsBase64: false)
        }
        throw ClientError.invalidSubscriptionResponse
    }

    private static func yamlFromJSON(_ contents: String) -> String? {
        guard let data = contents.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] || object is [Any] else {
            return nil
        }

        let profile: Any = if let proxies = object as? [Any] {
            proxySubscriptionProfile(with: proxies)
        } else {
            object
        }
        return yamlDocument(from: profile)
    }

    private static func isYAMLConfiguration(_ contents: String) -> Bool {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), !line.hasPrefix("---"),
                  let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let remainder = line[line.index(after: separator)...]
            guard remainder.isEmpty || remainder.first?.isWhitespace == true || remainder.first == "[" || remainder.first == "{" else {
                continue
            }
            if key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func yamlFromProxyLinks(_ contents: String) throws -> String? {
        let links = contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !links.isEmpty, links.allSatisfy({ $0.contains("://") }) else {
            return nil
        }

        var usedNames: [String: Int] = [:]
        let proxies = try links.enumerated().map { index, link in
            var proxy = try proxy(from: String(link), fallbackName: "Proxy \(index + 1)")
            let name = (proxy["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = name?.isEmpty == false ? name! : "Proxy \(index + 1)"
            let duplicateCount = usedNames[baseName, default: 0]
            usedNames[baseName] = duplicateCount + 1
            proxy["name"] = duplicateCount == 0 ? baseName : "\(baseName) \(duplicateCount + 1)"
            return proxy
        }
        return yamlDocument(from: proxySubscriptionProfile(with: proxies))
    }

    private static func proxySubscriptionProfile(with proxies: [Any]) -> [String: Any] {
        let proxyNames = proxies.compactMap { ($0 as? [String: Any])?["name"] as? String }
        return [
            "proxies": proxies,
            "proxy-groups": [[
                "name": "Proxy",
                "type": "select",
                "proxies": proxyNames + ["DIRECT"]
            ]],
            "rules": ["MATCH,Proxy"]
        ]
    }

    private static func proxy(from link: String, fallbackName: String) throws -> [String: Any] {
        guard let scheme = URLComponents(string: link)?.scheme?.lowercased() else {
            throw ClientError.invalidSubscriptionResponse
        }

        switch scheme {
        case "vmess":
            return try vmessProxy(from: link, fallbackName: fallbackName)
        case "ss":
            return try shadowsocksProxy(from: link, fallbackName: fallbackName)
        case "ssr":
            return try shadowsocksRProxy(from: link, fallbackName: fallbackName)
        case "vless", "trojan", "hysteria", "hysteria2", "hy2", "tuic", "socks", "socks5", "http", "https":
            return try URLProxy(link: link, scheme: scheme, fallbackName: fallbackName).make()
        default:
            throw ClientError.invalidSubscriptionResponse
        }
    }

    private static func vmessProxy(from link: String, fallbackName: String) throws -> [String: Any] {
        let payload = String(link.dropFirst("vmess://".count).split(separator: "#", maxSplits: 1)[0])
        guard let decoded = decodedBase64Contents(from: payload),
              let data = decoded.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = stringValue(values["add"]),
              let port = portValue(values["port"]),
              let uuid = stringValue(values["id"]) else {
            throw ClientError.invalidSubscriptionResponse
        }

        var proxy: [String: Any] = [
            "name": stringValue(values["ps"]) ?? fallbackName,
            "type": "vmess",
            "server": server,
            "port": port,
            "uuid": uuid,
            "alterId": intValue(values["aid"]) ?? 0,
            "cipher": stringValue(values["scy"]) ?? "auto"
        ]
        let network = stringValue(values["net"]) ?? "tcp"
        proxy["network"] = network
        if isEnabled(values["tls"]) { proxy["tls"] = true }
        copyString("servername", from: values["sni"], into: &proxy)
        copyString("client-fingerprint", from: values["fp"], into: &proxy)
        if isEnabled(values["allowInsecure"]) { proxy["skip-cert-verify"] = true }
        if let alpn = stringList(values["alpn"]) { proxy["alpn"] = alpn }

        let host = stringValue(values["host"])
        let path = stringValue(values["path"])
        switch network {
        case "ws":
            var options: [String: Any] = [:]
            if let path { options["path"] = path }
            if let host, !host.isEmpty { options["headers"] = ["Host": host] }
            if !options.isEmpty { proxy["ws-opts"] = options }
        case "grpc":
            if let path, !path.isEmpty { proxy["grpc-opts"] = ["grpc-service-name": path] }
        case "h2":
            var options: [String: Any] = [:]
            if let host, !host.isEmpty { options["host"] = host.split(separator: ",").map(String.init) }
            if let path, !path.isEmpty { options["path"] = path }
            if !options.isEmpty { proxy["h2-opts"] = options }
        default:
            break
        }
        return proxy
    }

    private static func shadowsocksProxy(from link: String, fallbackName: String) throws -> [String: Any] {
        let body = String(link.dropFirst("ss://".count))
        let (withoutFragment, name) = splitURLPart(body, separator: "#")
        let (authority, query) = splitURLPart(withoutFragment, separator: "?")
        let credentialsAndHost: String
        if authority.contains("@") {
            credentialsAndHost = authority
        } else if let decoded = decodedBase64Contents(from: authority) {
            credentialsAndHost = decoded
        } else {
            throw ClientError.invalidSubscriptionResponse
        }

        let parts = credentialsAndHost.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw ClientError.invalidSubscriptionResponse }
        let encodedCredentials = String(parts[0])
        let credentials = encodedCredentials.contains(":")
            ? decodeURLPart(encodedCredentials)
            : decodedBase64Contents(from: encodedCredentials) ?? decodeURLPart(encodedCredentials)
        let credentialParts = credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard credentialParts.count == 2,
              let endpoint = URLComponents(string: "ss://\(parts[1])"),
              let server = endpoint.host,
              let port = endpoint.port else {
            throw ClientError.invalidSubscriptionResponse
        }

        var proxy: [String: Any] = [
            "name": name ?? fallbackName,
            "type": "ss",
            "server": server,
            "port": port,
            "cipher": decodeURLPart(String(credentialParts[0])),
            "password": decodeURLPart(String(credentialParts[1]))
        ]
        if let plugin = queryValues(query ?? "")["plugin"], !plugin.isEmpty {
            let options = plugin.split(separator: ";", omittingEmptySubsequences: true)
            proxy["plugin"] = String(options[0])
            let pluginOptions = options.dropFirst().reduce(into: [String: String]()) { result, value in
                let pair = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                result[String(pair[0])] = pair.count == 2 ? String(pair[1]) : "true"
            }
            if !pluginOptions.isEmpty { proxy["plugin-opts"] = pluginOptions }
        }
        return proxy
    }

    private static func shadowsocksRProxy(from link: String, fallbackName: String) throws -> [String: Any] {
        let payload = String(link.dropFirst("ssr://".count))
        guard let decoded = decodedBase64Contents(from: payload) else {
            throw ClientError.invalidSubscriptionResponse
        }
        let parts = decoded.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let values = parts[0].split(separator: ":", omittingEmptySubsequences: false)
        guard values.count >= 6, let port = Int(values[1]) else {
            throw ClientError.invalidSubscriptionResponse
        }
        let query = parts.count == 2 ? queryValues(String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "?"))) : [:]
        var proxy: [String: Any] = [
            "name": decodedBase64Contents(from: query["remarks"] ?? "") ?? fallbackName,
            "type": "ssr",
            "server": String(values[0]),
            "port": port,
            "protocol": String(values[2]),
            "cipher": String(values[3]),
            "obfs": String(values[4]),
            "password": decodedBase64Contents(from: String(values[5])) ?? String(values[5])
        ]
        for (queryKey, yamlKey) in [("obfsparam", "obfs-param"), ("protoparam", "protocol-param")] {
            if let value = query[queryKey], let decodedValue = decodedBase64Contents(from: value) {
                proxy[yamlKey] = decodedValue
            }
        }
        return proxy
    }

    private static func decodedBase64Contents(from value: String) -> String? {
        let compact = value.components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.count >= 4,
              compact.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-").contains($0)
              }) else {
            return nil
        }
        let unpadded = compact.replacingOccurrences(of: "=", with: "")
        guard !unpadded.isEmpty, unpadded.count % 4 != 1 else { return nil }
        let normalized = unpadded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - unpadded.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return decoded
    }

    private static func yamlDocument(from object: Any) -> String {
        yamlLines(for: object, indentation: 0).joined(separator: "\n")
    }

    private static func yamlLines(for value: Any, indentation: Int) -> [String] {
        if let inline = yamlInlineValue(for: value) {
            return [String(repeating: " ", count: indentation) + inline]
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().flatMap { key in
                let item = dictionary[key]!
                let prefix = String(repeating: " ", count: indentation) + yamlKey(key) + ":"
                if let inline = yamlInlineValue(for: item) {
                    return ["\(prefix) \(inline)"]
                }
                return [prefix] + yamlLines(for: item, indentation: indentation + 2)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap { item in
                let prefix = String(repeating: " ", count: indentation) + "-"
                if let inline = yamlInlineValue(for: item) {
                    return ["\(prefix) \(inline)"]
                }
                return [prefix] + yamlLines(for: item, indentation: indentation + 2)
            }
        }
        return []
    }

    private static func yamlInlineValue(for value: Any) -> String? {
        if value is NSNull { return "null" }
        if let string = value as? String { return yamlQuoted(string) }
        if let number = value as? NSNumber {
            return String(cString: number.objCType) == "c" ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        if let dictionary = value as? [String: Any], dictionary.isEmpty { return "{}" }
        if let array = value as? [Any], array.isEmpty { return "[]" }
        return nil
    }

    private static func yamlKey(_ value: String) -> String {
        value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil ? value : yamlQuoted(value)
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            value.isEmpty ? nil : value
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }

    private static func portValue(_ value: Any?) -> Int? {
        guard let port = intValue(value), (1...65_535).contains(port) else { return nil }
        return port
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        guard let string = stringValue(value)?.lowercased() else { return false }
        return ["1", "true", "tls"].contains(string)
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let value = stringValue(value), !value.isEmpty else { return nil }
        let values = value.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private static func copyString(_ key: String, from value: Any?, into proxy: inout [String: Any]) {
        if let value = stringValue(value) { proxy[key] = value }
    }

    private static func splitURLPart(_ value: String, separator: Character) -> (String, String?) {
        let parts = value.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts[0]), parts.count == 2 ? decodeURLPart(String(parts[1])) : nil)
    }

    private static func decodeURLPart(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func queryValues(_ query: String) -> [String: String] {
        query.split(separator: "&", omittingEmptySubsequences: true).reduce(into: [:]) { values, item in
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { return }
            values[decodeURLPart(String(key))] = parts.count == 2 ? decodeURLPart(String(parts[1])) : ""
        }
    }

    private struct URLProxy {
        let link: String
        let scheme: String
        let fallbackName: String

        func make() throws -> [String: Any] {
            guard let components = URLComponents(string: link),
                  let server = components.host,
                  let port = components.port else {
                throw ClientError.invalidSubscriptionResponse
            }
            let query = components.queryItems?.reduce(into: [String: String]()) { values, item in
                values[item.name] = item.value ?? ""
            } ?? [:]
            let name = decodeURLPart(components.fragment ?? "").isEmpty ? fallbackName : decodeURLPart(components.fragment ?? "")
            let user = decodeURLPart(components.user ?? "")
            let password = decodeURLPart(components.password ?? "")

            switch scheme {
            case "vless":
                guard !user.isEmpty else { throw ClientError.invalidSubscriptionResponse }
                var proxy: [String: Any] = [
                    "name": name, "type": "vless", "server": server, "port": port, "uuid": user,
                    "network": query["type"] ?? "tcp", "udp": true
                ]
                copyOptional("flow", from: query["flow"], into: &proxy)
                copyOptional("encryption", from: query["encryption"], into: &proxy)
                applyTransport(query, to: &proxy)
                return proxy
            case "trojan":
                guard !user.isEmpty else { throw ClientError.invalidSubscriptionResponse }
                var proxy: [String: Any] = [
                    "name": name, "type": "trojan", "server": server, "port": port, "password": user, "udp": true
                ]
                applyTransport(query, to: &proxy)
                return proxy
            case "hysteria":
                guard !user.isEmpty else { throw ClientError.invalidSubscriptionResponse }
                var proxy: [String: Any] = [
                    "name": name, "type": "hysteria", "server": server, "port": port, "auth-str": user
                ]
                copyOptional("up", from: query["upmbps"], into: &proxy)
                copyOptional("down", from: query["downmbps"], into: &proxy)
                applyTransport(query, to: &proxy)
                return proxy
            case "hysteria2", "hy2":
                guard !user.isEmpty else { throw ClientError.invalidSubscriptionResponse }
                var proxy: [String: Any] = [
                    "name": name, "type": "hysteria2", "server": server, "port": port, "password": user
                ]
                copyOptional("obfs", from: query["obfs"], into: &proxy)
                copyOptional("obfs-password", from: query["obfs-password"], into: &proxy)
                applyTransport(query, to: &proxy)
                return proxy
            case "tuic":
                guard !user.isEmpty else { throw ClientError.invalidSubscriptionResponse }
                var proxy: [String: Any] = [
                    "name": name, "type": "tuic", "server": server, "port": port, "uuid": user, "password": password
                ]
                for key in ["congestion_control", "udp_relay_mode"] {
                    copyOptional(key.replacingOccurrences(of: "_", with: "-"), from: query[key], into: &proxy)
                }
                applyTransport(query, to: &proxy)
                return proxy
            case "socks", "socks5":
                var proxy: [String: Any] = ["name": name, "type": "socks5", "server": server, "port": port]
                copyOptional("username", from: user, into: &proxy)
                copyOptional("password", from: password, into: &proxy)
                return proxy
            case "http", "https":
                var proxy: [String: Any] = ["name": name, "type": "http", "server": server, "port": port]
                if scheme == "https" { proxy["tls"] = true }
                copyOptional("username", from: user, into: &proxy)
                copyOptional("password", from: password, into: &proxy)
                return proxy
            default:
                throw ClientError.invalidSubscriptionResponse
            }
        }

        private func applyTransport(_ query: [String: String], to proxy: inout [String: Any]) {
            let security = query["security"]?.lowercased()
            if ["tls", "reality"].contains(security) { proxy["tls"] = true }
            if query["insecure"] == "1" || query["allowInsecure"] == "1" { proxy["skip-cert-verify"] = true }
            copyOptional("servername", from: query["sni"] ?? query["peer"], into: &proxy)
            copyOptional("client-fingerprint", from: query["fp"], into: &proxy)
            if let alpn = query["alpn"], !alpn.isEmpty { proxy["alpn"] = alpn.split(separator: ",").map(String.init) }

            if security == "reality" {
                var options: [String: Any] = [:]
                copyOptional("public-key", from: query["pbk"], into: &options)
                copyOptional("short-id", from: query["sid"], into: &options)
                if !options.isEmpty { proxy["reality-opts"] = options }
            }

            switch query["type"] {
            case "ws":
                var options: [String: Any] = [:]
                copyOptional("path", from: query["path"], into: &options)
                if let host = query["host"], !host.isEmpty { options["headers"] = ["Host": host] }
                if !options.isEmpty { proxy["ws-opts"] = options }
            case "grpc":
                copyOptional("grpc-opts", from: query["serviceName"], into: &proxy, nestedKey: "grpc-service-name")
            default:
                break
            }
        }

        private func copyOptional(_ key: String, from value: String?, into dictionary: inout [String: Any], nestedKey: String? = nil) {
            guard let value, !value.isEmpty else { return }
            if let nestedKey {
                dictionary[key] = [nestedKey: value]
            } else {
                dictionary[key] = value
            }
        }
    }
}
