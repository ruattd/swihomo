import Foundation

/// The most recent iCloud sync event per source, shown on the sync settings
/// page with its timestamp. The settings controller (KVS side) and the
/// profile engine (CloudKit side) each own a slot so neither masks the
/// other. Transient by design: not persisted across launches.
@MainActor
final class SyncStatusStore: ObservableObject {
    static let shared = SyncStatusStore()

    /// Which sync pipeline produced an event.
    enum Source {
        /// Key-value store: preferences and the sync configuration itself.
        case preferences
        /// CloudKit: profiles and global overrides.
        case profiles
    }

    struct Event: Equatable {
        let date: Date
        let message: String
        let isError: Bool
    }

    @Published private(set) var preferencesEvent: Event?
    @Published private(set) var profilesEvent: Event?

    private init() {}

    func record(_ message: String, source: Source, isError: Bool = false) {
        let event = Event(date: Date(), message: message, isError: isError)
        switch source {
        case .preferences: preferencesEvent = event
        case .profiles: profilesEvent = event
        }
    }

    /// Records a failure with the underlying error's description appended.
    func recordFailure(_ message: String, source: Source, _ error: Error) {
        record("\(message): \(error.localizedDescription)", source: source, isError: true)
    }
}
