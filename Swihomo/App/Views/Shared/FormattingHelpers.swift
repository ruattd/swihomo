import SwiftUI

func subscriptionSummary(_ subscriptionInfo: MihomoSubscriptionInfo) -> Text {
    var summary = Text("\(byteCount(subscriptionInfo.used)) / \(byteCount(subscriptionInfo.total))")
    if let usageFraction = subscriptionInfo.usageFraction {
        summary = summary + Text(" (\(Int((usageFraction * 100).rounded()))%")
        if let expirationDate = subscriptionInfo.expirationDate {
            summary = summary + Text(", ") + Text("resources.expires") + Text(expirationDate, format: .dateTime.year().month().day())
        }
        return summary + Text(")")
    }
    if let expirationDate = subscriptionInfo.expirationDate {
        return summary + Text(" (") + Text("resources.expires") + Text(expirationDate, format: .dateTime.year().month().day()) + Text(")")
    }
    return summary
}

func address(_ host: String, port: String) -> String {
    guard !host.isEmpty else { return "Not reported" }
    guard !port.isEmpty else { return host }
    return "\(host):\(port)"
}
