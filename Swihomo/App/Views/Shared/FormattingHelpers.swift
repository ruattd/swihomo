import SwiftUI

// Usage only — the expiration date shows as its own row next to it. `display` selects
// used vs. remaining bytes; callers hide the row entirely for `.hidden`.
func subscriptionSummary(
    _ subscriptionInfo: MihomoSubscriptionInfo,
    display: SubscriptionInfoDisplay = .used
) -> Text {
    let value: Int64
    let percent: Int?
    if let usageFraction = subscriptionInfo.usageFraction {
        switch display {
        case .hidden, .used:
            value = subscriptionInfo.used
            percent = Int((usageFraction * 100).rounded())
        case .remaining:
            value = max(subscriptionInfo.total - subscriptionInfo.used, 0)
            percent = Int(((1 - usageFraction) * 100).rounded())
        }
    } else {
        switch display {
        case .hidden, .used:
            value = subscriptionInfo.used
        case .remaining:
            value = max(subscriptionInfo.total - subscriptionInfo.used, 0)
        }
        percent = nil
    }
    if let percent {
        return Text("\(byteCount(value)) / \(byteCount(subscriptionInfo.total)) (\(percent)%)")
    }
    return Text("\(byteCount(value)) / \(byteCount(subscriptionInfo.total))")
}

func address(_ host: String, port: String) -> String {
    guard !host.isEmpty else { return "Not reported" }
    guard !port.isEmpty else { return host }
    return "\(host):\(port)"
}
