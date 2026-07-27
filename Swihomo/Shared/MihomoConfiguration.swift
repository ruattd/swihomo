import Foundation

struct MihomoRuntimeConfiguration {
    let profileYAML: Data
    let overridesYAML: Data
}

enum MihomoConfigurationBuilder {
    static func makeRuntimeConfiguration(
        profileContents: String,
        overrides: ProxyOverrides
    ) throws -> MihomoRuntimeConfiguration {
        guard !profileContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingProfile
        }
        return MihomoRuntimeConfiguration(
            profileYAML: Data(profileContents.utf8),
            overridesYAML: Data(makeOverrideEnvelope(overrides).utf8)
        )
    }

    private static func makeOverrideEnvelope(_ overrides: ProxyOverrides) -> String {
        let customOverrides = yamlBlock(overrides.customYAML)
        let commonOverrides = yamlBlock(makeCommonOverridesYAML(overrides))
        return """
        __swihomo_custom_override: |
        \(customOverrides)
        __swihomo_common_override: |
        \(commonOverrides)
        """
    }

    private static func makeCommonOverridesYAML(_ overrides: ProxyOverrides) -> String {
        let secret = yamlQuoted(overrides.controllerSecret)
        return """
        mode: \(overrides.mode.rawValue)
        mixed-port: \(overrides.mixedPort)
        allow-lan: \(overrides.allowLAN)
        ipv6: \(overrides.ipv6Enabled)
        external-controller: 127.0.0.1:\(overrides.controllerPort)
        secret: \(secret)
        dns:
          enable: \(overrides.dnsEnabled)
        """
    }

    private static func yamlBlock(_ contents: String) -> String {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  \($0)" }
            .joined(separator: "\n")
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
