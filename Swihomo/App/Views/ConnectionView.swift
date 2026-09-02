import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("connectionSortCriterion") private var connectionSortCriterion = ConnectionSortCriterion.process
    @AppStorage("connectionSortDirection") private var connectionSortDirection = ProxySortDirection.ascending
    @State private var selectedConnection: MihomoConnectionActivity?
    @State private var connectionSearchText = ""
    @State private var showsBackToTopButton = false
    @State private var showingCloseAllConfirmation = false

    private var showsConnections: Bool {
        model.tunnelStatus == .connected
    }

    var body: some View {
        Group {
            if showsConnections {
                connectedDashboard
            } else {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)
                    connectionSummary
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            }
        }
        .animation(reduceMotion ? nil : .bouncy, value: showsConnections)
        .animation(reduceMotion ? nil : .snappy, value: model.isConnected)
        .animation(reduceMotion ? nil : .snappy, value: model.snapshot.activeProfileID)
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
        .onChange(of: showsConnections) { _, isConnected in
            if !isConnected {
                showsBackToTopButton = false
            }
        }
        .navigationDestination(item: $selectedConnection) { activity in
            ConnectionDetailView(activity: activity, model: model)
        }
    }

    private var connectionSummary: some View {
        VStack(spacing: showsConnections ? 10 : 24) {
            Image(systemName: model.isConnected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: showsConnections ? 48 : 72))
                .foregroundStyle(model.isConnected ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, value: model.isConnected)
            Text(LocalizedStringKey(model.connectionStatusLocalizationKey))
                .font(showsConnections ? .title2.bold() : .largeTitle.bold())
            Group {
                if let profile = model.snapshot.activeProfile {
                    Text(profile.name)
                } else {
                    Text("home.chooseConfiguration")
                }
            }
                .font(showsConnections ? .footnote : .body)
                .foregroundStyle(.secondary)
            if let profile = model.snapshot.activeProfile {
                Button(LocalizedStringKey(model.isConnected ? "common.disconnect" : "common.connect")) {
                    if model.isConnected {
                        model.disconnect()
                    } else {
                        Task { await model.connect(profile: profile) }
                    }
                }
                .liquidGlassButton(prominent: true)
                .controlSize(showsConnections ? .regular : .large)
            } else {
                Text("home.importProfiles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(maxWidth: showsConnections ? 620 : 480)
            HStack(spacing: showsConnections ? 22 : 28) {
                Metric(label: "home.mode", value: model.snapshot.overrides.mode.displayName, valueKey: model.snapshot.overrides.mode.localizationKey, compact: showsConnections)
                Metric(label: "navigation.profiles", value: "\(model.snapshot.profiles.count)", compact: showsConnections)
                Metric(label: "home.groups", value: "\(model.proxyGroups.count)", compact: showsConnections)
            }
        }
    }

    private var connections: [MihomoConnectionActivity] {
        model.sortedConnectionActivities(by: connectionSortCriterion, direction: connectionSortDirection)
    }

    private var filteredConnections: [MihomoConnectionActivity] {
        let query = connectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return connections }
        return connections.filter { activity in
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

    private var connectedDashboard: some View {
        ScrollViewReader { proxy in
            List {
                connectionSummary
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ConnectionDashboardScrollOffsetKey.self,
                                value: geometry.frame(in: .named("connection-dashboard-scroll")).minY
                            )
                        }
                    )
                    .id("connection-dashboard-top")
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                panelHeader
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))

                controlsRow
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))

                if filteredConnections.isEmpty {
                    ContentUnavailableView(
                        LocalizedStringKey(connections.isEmpty ? "connections.empty" : "connections.noMatch"),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(LocalizedStringKey(connections.isEmpty ? "connections.empty.description" : "connections.noMatch.description"))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredConnections) { activity in
                        Button {
                            selectedConnection = activity
                        } label: {
                            ConnectionRow(activity: activity)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .coordinateSpace(name: "connection-dashboard-scroll")
            .confirmationDialog(
                Text(LocalizedStringKey("connection.closeAll.confirmationTitle")),
                isPresented: $showingCloseAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("connection.closeAll", role: .destructive) {
                    Task { await model.closeAllConnections() }
                }
            } message: {
                Text(LocalizedStringKey("connection.closeAll.confirmationMessage"))
            }
            .onPreferenceChange(ConnectionDashboardScrollOffsetKey.self) { offset in
                let shouldShow = offset < -180
                guard shouldShow != showsBackToTopButton else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
                    showsBackToTopButton = shouldShow
                }
            }
            .searchable(text: $connectionSearchText, prompt: "connections.search")
            .overlay(alignment: .bottomTrailing) {
                if showsBackToTopButton {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            proxy.scrollTo("connection-dashboard-top", anchor: .top)
                        }
                    } label: {
                        Label("common.backToTop", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 42, height: 42)
                    }
                    .liquidGlassButton()
                    .accessibilityLabel("common.backToTop")
                    .padding(20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

}

private struct ConnectionDashboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct Metric: View {
    let label: LocalizedStringKey
    let value: String
    let valueKey: String?
    var compact = false

    init(label: LocalizedStringKey, value: String, valueKey: String? = nil, compact: Bool = false) {
        self.label = label
        self.value = value
        self.valueKey = valueKey
        self.compact = compact
    }

    var body: some View {
        VStack(spacing: 4) {
            if let valueKey {
                Text(LocalizedStringKey(valueKey))
                    .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
            } else {
                Text(value)
                    .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension DashboardView {

    fileprivate var panelHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("connections.live.title")
                    .font(.headline)
                Text("connections.live.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(connections.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.14), in: Capsule())
        }
    }

    fileprivate var controlsRow: some View {
        HStack(spacing: 10) {
                Button(role: .destructive) {
                    showingCloseAllConfirmation = true
                } label: {
                    Label("connection.closeAll", systemImage: "xmark.circle")
                }
                                    .liquidGlassButton()
                .disabled(connections.isEmpty || model.isClosingAllConnections)
                Spacer()
                Menu {
                    Section("common.sortBy") {
                        ForEach(ConnectionSortCriterion.allCases) { criterion in
                            Button {
                                connectionSortCriterion = criterion
                                connectionSortDirection = criterion == .speed ? .descending : .ascending
                            } label: {
                                Label(
                                    LocalizedStringKey(criterion.localizationKey),
                                    systemImage: connectionSortCriterion == criterion ? "checkmark" : "circle"
                                )
                            }
                        }
                    }
                    Section("common.direction") {
                        ForEach(ProxySortDirection.allCases) { direction in
                            Button {
                                connectionSortDirection = direction
                            } label: {
                                Label(
                                    LocalizedStringKey(direction.localizationKey),
                                    systemImage: connectionSortDirection == direction ? "checkmark" : direction.systemImage
                                )
                            }
                        }
                    }
                } label: {
                    Label(
                        LocalizedStringKey(connectionSortCriterion.localizationKey),
                        systemImage: connectionSortDirection.systemImage
                    )
                        .font(.subheadline.weight(.medium))
                }
                .liquidGlassButton()
        }
    }
}

private struct ConnectionRow: View {
    let activity: MihomoConnectionActivity

    var body: some View {
        rowContent
            .padding(6)
            .contentCard()
            .contentShape(RoundedRectangle(cornerRadius: SurfaceMetrics.boxCornerRadius, style: .continuous))
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(activity.connection.processName), \(byteRate(activity.totalSpeed)), \(activity.connection.routingDescription)")
            .accessibilityHint("accessibility.connectionDetails")
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ConnectionProcessIcon(metadata: activity.connection.metadata)

                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.connection.processName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(activity.connection.destination)
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
                if activity.connection.routingDescription.isEmpty {
                    Text("connection.noMatchingRule")
                } else {
                    Text(activity.connection.routingDescription)
                }
            }
                .font(.caption2)
                .foregroundStyle(.cyan)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label(byteRate(activity.downloadSpeed), systemImage: "arrow.down")
                Label(byteRate(activity.uploadSpeed), systemImage: "arrow.up")
                Spacer()
                Text(byteRate(activity.totalSpeed))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let activity: MihomoConnectionActivity
    @ObservedObject var model: AppModel

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
        .navigationTitle(Text(LocalizedStringKey("connection.details")))
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
        NSWorkspace.shared.runningApplications.first { application in
            let matchesPath = !metadata.processPath.isEmpty && application.executableURL?.path == metadata.processPath
            let matchesBundleID = !metadata.process.isEmpty && application.bundleIdentifier == metadata.process
            let matchesName = !metadata.process.isEmpty && application.localizedName?.localizedCaseInsensitiveCompare(metadata.process) == .orderedSame
            return matchesPath || matchesBundleID || matchesName
        }?.icon
    }
#endif
}
