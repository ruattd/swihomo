import Foundation

/// The most recent iCloud sync event, shown on the sync settings page with
/// its timestamp. Written by the settings sync controller (KVS side) and the
/// profile sync engine (CloudKit side); both successes and failures land
/// here. Transient by design: not persisted across launches.
@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    struct Event: Equatable {
        let date: Date
        let message: String
        let isError: Bool
    }

    @Published private(set) var lastEvent: Event?

    private init() {}

    func record(_ message: String, isError: Bool = false) {
        lastEvent = Event(date: Date(), message: message, isError: isError)
    }

    /// Records a failure with the underlying error's description appended.
    func recordFailure(_ message: String, _ error: Error) {
        record("\(message): \(error.localizedDescription)", isError: true)
    }
}
