import Foundation

actor SharedProfileRepository {
    private let fileManager = FileManager.default

    func loadSnapshot() throws -> ClientSnapshot {
        let manifest = try manifestURL()
        guard fileManager.fileExists(atPath: manifest.path) else {
            return .empty()
        }

        let data = try Data(contentsOf: manifest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClientSnapshot.self, from: data)
    }

    func createLocalProfile(name: String, contents: String) throws -> ClientSnapshot {
        try createProfile(name: name, source: .local, remoteURL: nil, contents: contents)
    }

    func createRemoteProfile(
        name: String,
        remoteURL: URL,
        customUserAgent: String?
    ) async throws -> ClientSnapshot {
        let contents = try await downloadProfile(at: remoteURL, customUserAgent: customUserAgent)
        return try createProfile(
            name: name,
            source: .remote,
            remoteURL: remoteURL,
            customUserAgent: customUserAgent,
            contents: contents
        )
    }

    func refreshProfile(_ id: UUID) async throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }),
              let remoteURL = snapshot.profiles[index].remoteURL else {
            throw ClientError.missingProfile
        }

        let contents = try await downloadProfile(
            at: remoteURL,
            customUserAgent: snapshot.profiles[index].customUserAgent
        )
        try writeProfileContents(contents, for: id)
        snapshot.profiles[index].updatedAt = .now
        snapshot.profiles[index].lastFetchedAt = .now
        try save(snapshot)
        return snapshot
    }

    func deleteProfile(_ id: UUID) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        snapshot.profiles.removeAll { $0.id == id }
        if snapshot.activeProfileID == id {
            snapshot.activeProfileID = nil
        }

        let configuration = try configurationURL(for: id)
        try? fileManager.removeItem(at: configuration)
        try save(snapshot)
        return snapshot
    }

    func activateProfile(_ id: UUID) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        guard snapshot.profiles.contains(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.activeProfileID = id
        try save(snapshot)
        return snapshot
    }

    func saveOverrides(_ overrides: ProxyOverrides) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        snapshot.overrides = overrides
        try save(snapshot)
        return snapshot
    }

    func runtimeConfiguration(for id: UUID) throws -> (profile: Profile, contents: String, overrides: ProxyOverrides) {
        let snapshot = try loadSnapshot()
        guard let profile = snapshot.profiles.first(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        let contents = try String(contentsOf: configurationURL(for: id), encoding: .utf8)
        return (profile, contents, snapshot.overrides)
    }

    private func createProfile(
        name: String,
        source: ProfileSource,
        remoteURL: URL?,
        customUserAgent: String? = nil,
        contents: String
    ) throws -> ClientSnapshot {
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidProfile
        }

        var snapshot = try loadSnapshot()
        let now = Date.now
        let profile = Profile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Profile" : name,
            source: source,
            remoteURL: remoteURL,
            customUserAgent: customUserAgent,
            createdAt: now,
            updatedAt: now,
            lastFetchedAt: source == .remote ? now : nil
        )
        try writeProfileContents(contents, for: profile.id)
        snapshot.profiles.append(profile)
        try save(snapshot)
        return snapshot
    }

    private func downloadProfile(at url: URL, customUserAgent: String? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let userAgent = customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue(userAgent?.isEmpty == false ? userAgent : MihomoCoreVersion.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw ClientError.httpFailure(response.statusCode)
        }
        guard let contents = String(data: data, encoding: .utf8),
              !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.invalidSubscriptionResponse
        }
        return contents
    }

    private func manifestURL() throws -> URL {
        try storageDirectory().appendingPathComponent("profiles.json")
    }

    private func configurationURL(for id: UUID) throws -> URL {
        try profilesDirectory().appendingPathComponent("\(id.uuidString).yaml")
    }

    private func writeProfileContents(_ contents: String, for id: UUID) throws {
        let directory = try profilesDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: configurationURL(for: id), atomically: true, encoding: .utf8)
    }

    private func save(_ snapshot: ClientSnapshot) throws {
        let root = try storageDirectory()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: manifestURL(), options: .atomic)
    }

    private func storageDirectory() throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ClientError.storageUnavailable
        }
        return applicationSupport.appendingPathComponent("Swihomo", isDirectory: true)
    }

    private func profilesDirectory() throws -> URL {
        try storageDirectory().appendingPathComponent("Profiles", isDirectory: true)
    }
}
