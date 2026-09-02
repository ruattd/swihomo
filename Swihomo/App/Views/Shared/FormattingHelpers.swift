import SwiftUI

// Usage only — the expiration date shows as its own row in the resource card.
func subscriptionSummary(_ subscriptionInfo: MihomoSubscriptionInfo) -> Text {
    if let usageFraction = subscriptionInfo.usageFraction {
        return Text("\(byteCount(subscriptionInfo.used)) / \(byteCount(subscriptionInfo.total)) (\(Int((usageFraction * 100).rounded()))%)")
    }
    return Text("\(byteCount(subscriptionInfo.used)) / \(byteCount(subscriptionInfo.total))")
}

func address(_ host: String, port: String) -> String {
    guard !host.isEmpty else { return "Not reported" }
    guard !port.isEmpty else { return host }
    return "\(host):\(port)"
}
