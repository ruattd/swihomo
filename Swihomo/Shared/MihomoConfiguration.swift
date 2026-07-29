import Foundation

struct MihomoRuntimeConfiguration {
    let profileYAML: Data
}

struct MihomoGeoDataRequirements {
    let requiresGeoIP: Bool
    let usesGeoIPDat: Bool
    let requiresGeoSite: Bool

    init(profileYAML: Data) {
        let contents = String(decoding: profileYAML, as: UTF8.self)
        requiresGeoIP = Self.containsRule("GEOIP", in: contents)
        requiresGeoSite = Self.containsRule("GEOSITE", in: contents)
        usesGeoIPDat = requiresGeoIP && Self.geodataModeIsEnabled(in: contents)
    }

    private static func containsRule(_ name: String, in contents: String) -> Bool {
        let pattern = "(?im)^\\s*-\\s*(?:[\\\"']\\s*)?.*\\b\(name)\\s*,"
        return contents.range(of: pattern, options: .regularExpression) != nil
    }

    private static func geodataModeIsEnabled(in contents: String) -> Bool {
        let pattern = "(?im)^\\s*geodata-mode\\s*:\\s*true\\s*(?:#.*)?$"
        return contents.range(of: pattern, options: .regularExpression) != nil
    }
}

enum MihomoConfigurationBuilder {
    static func makeRuntimeConfiguration(profileContents: String) throws -> MihomoRuntimeConfiguration {
        guard !profileContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingProfile
        }
        return MihomoRuntimeConfiguration(profileYAML: Data(profileContents.utf8))
    }

    static func standardOverridesYAML(_ overrides: ProxyOverrides) -> String {
        let secret = yamlQuoted(overrides.controllerSecret)
        return """
        mode: \(overrides.mode.rawValue)
        log-level: \(overrides.logLevel.rawValue)
        mixed-port: \(overrides.mixedPort)
        allow-lan: \(overrides.allowLAN)
        ipv6: \(overrides.ipv6Enabled)
        external-controller: 127.0.0.1:\(overrides.controllerPort)
        secret: \(secret)
        dns:
          enable: \(overrides.dnsEnabled)
        """
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
