import Foundation

actor SharedProfileRepository {
    private let fileManager = FileManager.default

    private struct DownloadedProfile {
        let contents: String
        let subscriptionInfo: MihomoSubscriptionInfo?
    }

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
        var snapshot = try loadSnapshot()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }),
              let remoteURL = snapshot.profiles[index].remoteURL else {
            throw ClientError.missingProfile
        }

        let downloadedProfile = try await downloadProfile(
            at: remoteURL,
            customUserAgent: snapshot.profiles[index].customUserAgent
        )
        try writeProfileContents(downloadedProfile.contents, for: id)
        snapshot.profiles[index].updatedAt = .now
        snapshot.profiles[index].lastFetchedAt = .now
        snapshot.profiles[index].subscriptionInfo = downloadedProfile.subscriptionInfo
        try save(snapshot)
        return snapshot
    }

    func updateRemoteProfile(
        _ id: UUID,
        name: String,
        remoteURL: URL,
        customUserAgent: String?
    ) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
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

    func setCustomOverridesEnabled(_ isEnabled: Bool, for id: UUID) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.profiles[index].customOverridesEnabled = isEnabled
        try save(snapshot)
        return snapshot
    }

    func setCustomOverrideYAML(_ contents: String, for id: UUID) throws -> ClientSnapshot {
        var snapshot = try loadSnapshot()
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == id }) else {
            throw ClientError.missingProfile
        }
        snapshot.profiles[index].customOverrideYAML = contents
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
        contents: String,
        subscriptionInfo: MihomoSubscriptionInfo? = nil
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
            lastFetchedAt: source == .remote ? now : nil,
            subscriptionInfo: subscriptionInfo
        )
        try writeProfileContents(contents, for: profile.id)
        snapshot.profiles.append(profile)
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
