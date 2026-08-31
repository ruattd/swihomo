import Foundation

func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func byteRate(_ value: Int64) -> String {
    "\(byteCount(value))/s"
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
