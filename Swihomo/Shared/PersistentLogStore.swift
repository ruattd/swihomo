import Foundation

final class PersistentLogStore: @unchecked Sendable {
    private static let maximumEntries = 1_000

    private let queue = DispatchQueue(label: "com.swihomo.log-store")
    // Encoding + atomic disk writes happen here so callers (often the main thread)
    // never block on IO. Serial ⇒ writes stay ordered, last one wins.
    private let persistQueue = DispatchQueue(label: "com.swihomo.log-store.persist", qos: .utility)
    private let fileURL: URL?
    private var storedEntries: [LogEntry]

    init(directoryName: String) {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fileURL = nil
            storedEntries = []
            return
        }

        let directory = applicationSupport
            .appendingPathComponent("Swihomo", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("entries.json")
        self.fileURL = fileURL
        storedEntries = Self.load(from: fileURL)
    }

    func entries() -> [LogEntry] {
        queue.sync { storedEntries }
    }

    @discardableResult
    func append(source: LogSource, module: String, level: LogLevel, message: String) -> [LogEntry] {
        queue.sync {
            appendLocked(LogEntry(source: source, module: module, level: level, message: message))
            return storedEntries
        }
    }

    func appendAsynchronously(source: LogSource, module: String, level: LogLevel, message: String) {
        queue.async {
            self.appendLocked(LogEntry(source: source, module: module, level: level, message: message))
        }
    }

    @discardableResult
    func replace(source: LogSource, with entries: [LogEntry]) -> [LogEntry] {
        queue.sync {
            storedEntries.removeAll { $0.source == source }
            storedEntries.append(contentsOf: entries)
            storedEntries.sort { $0.timestamp < $1.timestamp }
            trimLocked()
            schedulePersistLocked()
            return storedEntries
        }
    }

    @discardableResult
    func clear(source: LogSource? = nil) -> [LogEntry] {
        queue.sync {
            if let source {
                storedEntries.removeAll { $0.source == source }
            } else {
                storedEntries = []
            }
            schedulePersistLocked()
            return storedEntries
        }
    }

    private func appendLocked(_ entry: LogEntry) {
        storedEntries.append(entry)
        trimLocked()
        schedulePersistLocked()
    }

    private func trimLocked() {
        storedEntries = Self.trimmed(storedEntries)
    }

    // Must be called on `queue`; snapshots and hops to `persistQueue`.
    private func schedulePersistLocked() {
        guard let fileURL else { return }
        let snapshot = storedEntries
        persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from fileURL: URL) -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return []
        }
        return trimmed(entries)
    }

    private static func trimmed(_ entries: [LogEntry]) -> [LogEntry] {
        var result = entries.sorted { $0.timestamp < $1.timestamp }
        for source in LogSource.allCases {
            var excess = result.count(where: { $0.source == source }) - maximumEntries
            guard excess > 0 else { continue }
            result.removeAll { entry in
                guard entry.source == source, excess > 0 else { return false }
                excess -= 1
                return true
            }
        }
        return result
    }
}
