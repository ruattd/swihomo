import SwiftUI
#if os(macOS)
import AppKit
#endif

// Shell only: monitoring lifecycle, selection, and the destination. The list lives in
// ConnectionListView so unrelated AppModel publishes (log stream, traffic) never touch it.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    #if os(iOS)
    @Environment(\.pushCompactRoute) private var pushCompactRoute
    #endif
    @AppStorage("connectionSortCriterion") private var connectionSortCriterion = ConnectionSortCriterion.process
    @AppStorage("connectionSortDirection") private var connectionSortDirection = ProxySortDirection.ascending
    @State private var selectedConnection: MihomoConnectionActivity?

    private var showsConnections: Bool {
        model.tunnelStatus == .connected
    }

    var body: some View {
        ConnectionListView(
            activities: connections,
            showsConnections: showsConnections,
            isClosingAll: model.isClosingAllConnections,
            onCloseAll: { await model.closeAllConnections() },
            onSelect: { activity in
                #if os(iOS)
                if let pushCompactRoute {
                    pushCompactRoute(.connection(activity))
                    return
                }
                #endif
                selectedConnection = activity
            }
        )
        .onAppear {
            model.setConnectionMonitoringEnabled(true)
        }
        .task(id: showsConnections) {
            guard showsConnections else { return }
            model.setConnectionMonitoringEnabled(true)
        }
        .onDisappear {
            model.setConnectionMonitoringEnabled(false)
        }
        // Registered only when no outer compact stack is live: a path-based
        // stack must not contain item-based destinations (AnyNavigationPath
        // comparisonTypeMismatch crash). The compact layout pushes
        // CompactRoute.connection through its own path instead.
        .modifier(ConnectionDetailDestination(selected: $selectedConnection, enabled: connectionDetailDestinationEnabled))
    }

    /// False in the iOS compact tab layout, where the outer stack routes
    /// connection drill-ins through CompactRoute instead.
    private var connectionDetailDestinationEnabled: Bool {
        #if os(iOS)
        pushCompactRoute == nil
        #else
        true
        #endif
    }

    private var connections: [MihomoConnectionActivity] {
        model.sortedConnectionActivities(by: connectionSortCriterion, direction: connectionSortDirection)
    }
}

/// Applies the connection-detail destination unless an outer compact stack owns
/// connection routing (then DashboardView forwards taps to that stack's path).
private struct ConnectionDetailDestination: ViewModifier {
    @Binding var selected: MihomoConnectionActivity?
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(item: $selected) { activity in
                ConnectionDetailView(activity: activity)
            }
        } else {
            content
        }
    }
}

// Toolbar content for the connections page, rendered by the container on macOS (via
// ChromeProvider) and in-page on iOS. Reads model/AppStorage directly so it stays
// reactive no matter which view graph renders it.
private struct ConnectionToolbarContent: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("connectionSortCriterion") private var sortCriterion = ConnectionSortCriterion.process
    @AppStorage("connectionSortDirection") private var sortDirection = ProxySortDirection.ascending
    @Binding var showingCloseAllConfirmation: Bool

    var body: some View {
        Button(role: .destructive) {
            showingCloseAllConfirmation = true
        } label: {
            Label("connection.closeAll", systemImage: "xmark.circle")
        }
        .disabled(model.connectionActivities.isEmpty || model.isClosingAllConnections)

        Menu {
            Section("common.sortBy") {
                ForEach(ConnectionSortCriterion.allCases) { criterion in
                    Button {
                        sortCriterion = criterion
                        sortDirection = criterion == .speed ? .descending : .ascending
                    } label: {
                        Label(
                            LocalizedStringKey(criterion.localizationKey),
                            systemImage: sortCriterion == criterion ? "checkmark" : "circle"
                        )
                    }
                }
            }
            Section("common.direction") {
                ForEach(ProxySortDirection.allCases) { direction in
                    Button {
                        sortDirection = direction
                    } label: {
                        Label(
                            LocalizedStringKey(direction.localizationKey),
                            systemImage: sortDirection == direction ? "checkmark" : direction.systemImage
                        )
                    }
                }
            }
        } label: {
            Label(LocalizedStringKey(sortCriterion.localizationKey), systemImage: sortDirection.systemImage)
                .font(.subheadline.weight(.medium))
        }
    }
}

// Equatable shell around the live list: identical inputs skip the whole subtree — the
// Form and its per-section rows never diff against a refresh that changed nothing.
// Actions are compared by identity of intent, so == ignores the closures.
private struct ConnectionListView: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("connectionSortCriterion") private var connectionSortCriterion = ConnectionSortCriterion.process
    @AppStorage("connectionSortDirection") private var connectionSortDirection = ProxySortDirection.ascending
    @State private var showingCloseAllConfirmation = false
    @State private var connectionSearchText = ""
    // While the user is scrolling, the list renders this frozen snapshot instead of the
    // live activities — a mid-scroll publish otherwise invalidates cells mid-frame and
    // drops scroll frames.
    @State private var frozenActivities: [MihomoConnectionActivity]?

    let activities: [MihomoConnectionActivity]
    let showsConnections: Bool
    let isClosingAll: Bool
    let onCloseAll: () async -> Void
    let onSelect: (MihomoConnectionActivity) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.activities == rhs.activities
            && lhs.showsConnections == rhs.showsConnections
            && lhs.isClosingAll == rhs.isClosingAll
    }

    private var displayedActivities: [MihomoConnectionActivity] {
        frozenActivities ?? activities
    }

    var body: some View {
        // Live connections only — one connection per section, its row the section's
        // single content (same shape as resources/profiles).
        Form {
            ForEach(filteredConnections) { activity in
                Section {
                    Button {
                        onSelect(activity)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ConnectionRow(
                                metadata: activity.connection.metadata,
                                processName: activity.connection.processName,
                                destination: activity.connection.destination,
                                routingDescription: activity.connection.routingDescription
                            )
                            ConnectionSpeeds(
                                uploadSpeed: activity.uploadSpeed,
                                downloadSpeed: activity.downloadSpeed
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Plain buttons only hit-test covered pixels without an explicit shape.
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(activity.connection.processName), \(byteRate(activity.totalSpeed)), \(activity.connection.routingDescription)")
                        .accessibilityHint("accessibility.connectionDetails")
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
            }
        }
        .formStyle(.grouped)
        .compactSectionSpacing()
        .uniformTopScrollEdge()
        .freezeWhileScrolling(activities, into: $frozenActivities)
        .overlay {
            if !showsConnections {
                ContentUnavailableView(
                    LocalizedStringKey("connections.connectToView"),
                    systemImage: "network.slash",
                    description: Text(LocalizedStringKey("connections.connectToView.description"))
                )
                .transition(.opacity)
            } else if activities.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("connections.empty"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(LocalizedStringKey("connections.empty.description"))
                )
                .transition(.opacity)
            } else if filteredConnections.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("connections.noMatch"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(LocalizedStringKey("connections.noMatch.description"))
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsConnections)
        .animation(reduceMotion ? nil : .snappy, value: activities.isEmpty)
        #if os(macOS)
        // Chrome is hoisted to the detail container; per-page .toolbar/.searchable
        // inside nested hosting controllers collide in the shared window toolbar.
        .background(ChromeProvider(
            section: .connection,
            toolbar: { AnyView(ConnectionToolbarContent(showingCloseAllConfirmation: $showingCloseAllConfirmation)) },
            searchText: $connectionSearchText,
            searchPrompt: "connections.search"
        ))
        #else
        .searchable(text: $connectionSearchText, prompt: "connections.search")
        #endif
        .confirmationDialog(
            Text(LocalizedStringKey("connection.closeAll.confirmationTitle")),
            isPresented: $showingCloseAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("connection.closeAll", role: .destructive) {
                Task { await onCloseAll() }
            }
        } message: {
            Text(LocalizedStringKey("connection.closeAll.confirmationMessage"))
        }
        #if !os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ConnectionToolbarContent(showingCloseAllConfirmation: $showingCloseAllConfirmation)
            }
        }
        #endif
    }

    private var filteredConnections: [MihomoConnectionActivity] {
        let query = connectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return displayedActivities }
        return displayedActivities.filter { activity in
            let metadata = activity.connection.metadata
            return [
                activity.connection.processName,
                activity.connection.destination,
                metadata.destinationIP,
                metadata.remoteDestination,
                address(metadata.destinationIP, port: metadata.destinationPort)
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

// Static per-connection content, keyed on exactly the fields it displays. Synthesized
// Equatable skips the row (and its section container) whenever a refresh only moved
// the speeds or transfer totals.
private struct ConnectionRow: View, Equatable {
    let metadata: MihomoConnectionMetadata
    let processName: String
    let destination: String
    let routingDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ConnectionProcessIcon(metadata: metadata)

                VStack(alignment: .leading, spacing: 3) {
                    Text(processName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if routingDescription.isEmpty {
                    Text("connection.noMatchingRule")
                } else {
                    Text(routingDescription)
                }
            }
                .font(.caption2)
                .foregroundStyle(.cyan)
                .lineLimit(2)
        }
    }
}

// The only part of a row that changes every refresh — isolated so its re-render is a
// three-label HStack instead of the whole section.
private struct ConnectionSpeeds: View {
    let uploadSpeed: Int64
    let downloadSpeed: Int64

    private var totalSpeed: Int64 { uploadSpeed + downloadSpeed }

    var body: some View {
        HStack(spacing: 10) {
            Label(byteRate(downloadSpeed), systemImage: "arrow.down")
            Label(byteRate(uploadSpeed), systemImage: "arrow.up")
            Spacer()
            Text(byteRate(totalSpeed))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let activity: MihomoConnectionActivity
    @EnvironmentObject private var model: AppModel

    private var currentActivity: MihomoConnectionActivity {
        model.connectionActivities.first { $0.id == activity.id } ?? activity
    }

    private var connection: MihomoConnection { currentActivity.connection }
    private var metadata: MihomoConnectionMetadata { connection.metadata }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ConnectionProcessIcon(metadata: metadata)
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.processName)
                            .font(.headline)
                        Text(connection.destination)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("connections.liveSpeed") {
                DetailValueRow(label: "traffic.download", value: byteRate(currentActivity.downloadSpeed))
                DetailValueRow(label: "traffic.upload", value: byteRate(currentActivity.uploadSpeed))
                DetailValueRow(label: "traffic.total", value: byteRate(currentActivity.totalSpeed))
            }

            Section("connections.traffic") {
                DetailValueRow(label: "traffic.downloaded", value: byteCount(connection.download))
                DetailValueRow(label: "traffic.uploaded", value: byteCount(connection.upload))
                if let startedAt = connection.startedAt {
                    DetailValueRow(label: "traffic.started", value: startedAt)
                }
            }

            Section("routing.title") {
                DetailValueRow(label: "routing.rule", value: connection.rule)
                DetailValueRow(label: "routing.rulePayload", value: connection.rulePayload)
                if !connection.proxyChainDescription.isEmpty {
                    DetailValueRow(label: "routing.proxyChain", value: connection.proxyChainDescription)
                }
                if !connection.providerChainDescription.isEmpty {
                    DetailValueRow(label: "routing.providerChain", value: connection.providerChainDescription)
                }
            }

            Section("navigation.connection") {
                DetailValueRow(label: "connection.protocol", value: [metadata.network, metadata.type].filter { !$0.isEmpty }.joined(separator: " / "))
                DetailValueRow(label: "common.source", value: address(metadata.sourceIP, port: metadata.sourcePort))
                DetailValueRow(label: "connection.destination", value: address(metadata.destinationIP, port: metadata.destinationPort))
                if !metadata.host.isEmpty {
                    DetailValueRow(label: "connection.host", value: metadata.host)
                }
                if !metadata.remoteDestination.isEmpty {
                    DetailValueRow(label: "connection.remoteDestination", value: metadata.remoteDestination)
                }
                if !metadata.processPath.isEmpty {
                    DetailValueRow(label: "connection.processPath", value: metadata.processPath)
                }
            }
        }
        .detailPageTitle("connection.details")
        // macOS: chrome bridging from nested hosting controllers collides in the
        // shared window toolbar; the close action stays available in the list.
        #if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .destructive) {
                    Task {
                        if await model.closeConnection(id: activity.id) {
                            dismiss()
                        }
                    }
                } label: {
                    Label("common.close", systemImage: "xmark.circle")
                }
                .disabled(model.closingConnectionIDs.contains(activity.id))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done") { dismiss() }
            }
        }
        #endif
    }
}

private struct DetailValueRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent(label) {
            if value.isEmpty {
                Text("common.notReported")
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ConnectionProcessIcon: View {
    let metadata: MihomoConnectionMetadata

    var body: some View {
#if os(macOS)
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            fallbackIcon
        }
#else
        fallbackIcon
#endif
    }

    private var fallbackIcon: some View {
        Image(systemName: "app.dashed")
            .font(.title3.weight(.medium))
            .foregroundStyle(.cyan)
            .frame(width: 36, height: 36)
            .background(Color.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

#if os(macOS)
    private var icon: NSImage? {
        Self.iconCache.icon(for: metadata)
    }

    private static let iconCache = ProcessIconCache()
#endif
}

#if os(macOS)
// Process icons were resolved per body evaluation: every rendered row re-scanned
// NSWorkspace.runningApplications and synchronously disk-loaded the NSImage.
// Cache hits AND misses by process path/name so each process pays the lookup once.
private final class ProcessIconCache: @unchecked Sendable {
    private let lock = NSLock()
    private let icons = NSCache<NSString, NSImage>()
    private let misses = NSMutableSet()

    func icon(for metadata: MihomoConnectionMetadata) -> NSImage? {
        let key = metadata.processPath.isEmpty ? metadata.process : metadata.processPath
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let cacheKey = key as NSString
        if let cached = icons.object(forKey: cacheKey) { return cached }
        if misses.contains(cacheKey) { return nil }
        guard let found = Self.lookup(metadata) else {
            misses.add(cacheKey)
            return nil
        }
        icons.setObject(found, forKey: cacheKey)
        return found
    }

    private static func lookup(_ metadata: MihomoConnectionMetadata) -> NSImage? {
        NSWorkspace.shared.runningApplications.first { application in
            let matchesPath = !metadata.processPath.isEmpty && application.executableURL?.path == metadata.processPath
            let matchesBundleID = !metadata.process.isEmpty && application.bundleIdentifier == metadata.process
            let matchesName = !metadata.process.isEmpty && application.localizedName?.localizedCaseInsensitiveCompare(metadata.process) == .orderedSame
            return matchesPath || matchesBundleID || matchesName
        }?.icon
    }
}
#endif
