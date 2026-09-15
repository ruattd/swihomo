import Foundation

func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func byteRate(_ value: Int64) -> String {
    // Three significant digits below 999 of the chosen unit, rounded integer
    // at or above. Binary (1024-based) units, KB at minimum so idle links
    // still read "0.00 KB/s" instead of switching to a B unit.
    let units = ["KB", "MB", "GB"]
    var rate = Double(max(value, 0)) / 1024
    var unitIndex = 0
    while rate >= 1024, unitIndex < units.count - 1 {
        rate /= 1024
        unitIndex += 1
    }
    // Thresholds sit half a last-digit step below the boundary so rounding
    // (e.g. 9.996 -> "10.0", 99.96 -> "100") never emits four significant digits.
    let decimals = rate < 9.995 ? 2 : rate < 99.95 ? 1 : 0
    return "\(String(format: "%.\(decimals)f", rate)) \(units[unitIndex])/s"
}

/// Fully describes an error for logs: type, domain, code, every userInfo entry,
/// and the whole underlying-error chain. Shared by the app and the Packet Tunnel.
func verboseErrorDescription(_ error: Error) -> String {
    let nsError = error as NSError
    var details = [
        "type=\(String(reflecting: type(of: error)))",
        "domain=\(nsError.domain)",
        "code=\(nsError.code)",
        "description=\(nsError.localizedDescription)"
    ]

    if let reason = nsError.localizedFailureReason,
       !reason.isEmpty,
       reason != nsError.localizedDescription {
        details.append("reason=\(reason)")
    }
    if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
        details.append("suggestion=\(suggestion)")
    }

    let reportedKeys: Set<String> = [
        NSLocalizedDescriptionKey,
        NSLocalizedFailureReasonErrorKey,
        NSLocalizedRecoverySuggestionErrorKey,
        NSUnderlyingErrorKey
    ]
    let extraUserInfo = nsError.userInfo
        .filter { !reportedKeys.contains($0.key) }
        .map { "\($0.key)=\(String(describing: $0.value))" }
        .sorted()
    if !extraUserInfo.isEmpty {
        details.append("userInfo={\(extraUserInfo.joined(separator: ", "))}")
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
        details.append("underlying=[\(verboseErrorDescription(underlying))]")
    }
    return details.joined(separator: " | ")
}
