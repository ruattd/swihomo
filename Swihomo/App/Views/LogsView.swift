import SwiftUI

private enum LogFilter: String, CaseIterable, Identifiable {
    case all
    case app
    case core

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .app: "App"
        case .core: "Core"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "common.all"
        case .app: "common.app"
        case .core: "common.core"
        }
    }
}

private enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All levels"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "logs.allLevels"
        case .debug: "common.debug"
        case .info: "common.info"
        case .warning: "common.warning"
        case .error: "common.error"
        }
    }

    var level: LogLevel? {
        LogLevel(rawValue: rawValue)
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = LogFilter.all
    @State private var levelFilter = LogLevelFilter.all
    @State private var searchText = ""
    @State private var showingClearLogsConfirmation = false

    private var entries: [LogEntry] {
        model.logEntries
            .filter { filter == .all || $0.source.rawValue == filter.rawValue }
            .filter { levelFilter.level == nil || $0.level == levelFilter.level }
            .filter { entry in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [entry.module, entry.message, entry.source.displayName, entry.level.displayName]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            // Single lazy implementation for both platforms: macOS grouped Form lays out rows
            // eagerly (measured 10x slower with 5000 rows) and GroupedListStyle is iOS-only.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        GroupBox {
                            LogEntryRow(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .uniformTopScrollEdge()
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        LocalizedStringKey("logs.empty"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(LocalizedStringKey("logs.empty.description"))
                    )
                }
            }
            .navigationTitle(Text(LocalizedStringKey("navigation.logs")))
            .searchable(text: $searchText, prompt: "logs.search")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        sourceFilterSection
                        levelFilterSection
                    } label: {
                        Label(filter.titleKey, systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.medium))
                    }

                    Menu {
                        Button(role: .destructive) {
                            showingClearLogsConfirmation = true
                        } label: {
                            Label("logs.clearLogs", systemImage: "trash")
                        }
                    } label: {
                        Label("common.more", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                Text(LocalizedStringKey("logs.clearLogs.confirmationTitle")),
                isPresented: $showingClearLogsConfirmation,
                titleVisibility: .visible
            ) {
                Button("logs.clearApp", role: .destructive) {
                    Task { await model.clearLogs(source: .app) }
                }
                Button("logs.clearCore", role: .destructive) {
                    Task { await model.clearLogs(source: .core) }
                }
                Button("logs.clearAll", role: .destructive) {
                    Task { await model.clearLogs() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("logs.clearLogs.description"))
            }
            .task { await model.reloadLogs() }
        }
    }

    private var sourceFilterSection: some View {
        Section("common.source") {
            ForEach(LogFilter.allCases) { source in
                Button {
                    filter = source
                } label: {
                    Label(
                        source.titleKey,
                        systemImage: filter == source ? "checkmark" : "circle"
                    )
                }
            }
        }
    }

    private var levelFilterSection: some View {
        Section("common.level") {
            ForEach(LogLevelFilter.allCases) { level in
                Button {
                    levelFilter = level
                } label: {
                    Label(
                        level.titleKey,
                        systemImage: levelFilter == level ? "checkmark" : "circle"
                    )
                }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(entry.source.localizationKey))
                    .textCase(.uppercase)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(entry.source == .app ? .blue : .teal)
                Text("[\(entry.module)]")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(entry.level.localizationKey))
                    .textCase(.uppercase)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(levelColor)
            }
            Text(entry.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }
}
