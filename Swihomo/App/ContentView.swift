import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            HomeView()
                .navigationSplitViewColumnWidth(min: 360, ideal: 400, max: 460)
                .navigationDestination(for: HomeSection.self) { section in
                    FeatureDetailView(section: section)
                }
        } detail: {
            FeatureDetailView(section: .connection)
        }
        .navigationSplitViewStyle(.balanced)
#if os(macOS)
        .background(WindowToolbarBaselineHider())
#endif
        .overlay(alignment: .bottom) {
            if let error = model.errorMessage {
                ErrorBanner(message: error, dismiss: { model.dismissError() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.errorMessage)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't Complete Request")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

#if os(macOS)
private struct WindowToolbarBaselineHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarBaselineView {
        ToolbarBaselineView()
    }

    func updateNSView(_ nsView: ToolbarBaselineView, context: Context) {
        nsView.hideToolbarBaseline()
    }
}

private final class ToolbarBaselineView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideToolbarBaseline()
    }

    func hideToolbarBaseline() {
        // The SwiftUI navigation toolbar is attached after this background view.
        DispatchQueue.main.async { [weak self] in
            self?.window?.toolbar?.showsBaselineSeparator = false
        }
    }
}
#endif

private enum HomeSection: String, CaseIterable, Hashable, Identifiable {
    case connection
    case profiles
    case proxies
    case overrides
    case externalResources
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalResources: "Resources"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .connection: "bolt.shield"
        case .profiles: "doc.on.doc"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .overrides: "slider.horizontal.3"
        case .externalResources: "externaldrive.connected.to.line.below"
        case .logs: "doc.text.magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .connection: .cyan
        case .profiles: .indigo
        case .proxies: .orange
        case .overrides: .pink
        case .externalResources: .purple
        case .logs: .teal
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swihomo")
                        .font(.title.bold())
                    Text("Control center")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(HomeSection.allCases) { section in
                        NavigationLink(value: section) {
                            HomeFeatureCard(
                                section: section,
                                value: value(for: section),
                                subtitle: subtitle(for: section),
                                isHighlighted: section == .connection && model.isConnected
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
    }

    private func value(for section: HomeSection) -> String {
        switch section {
        case .connection:
            model.connectionStatusTitle
        case .profiles:
            "\(model.snapshot.profiles.count) profiles"
        case .proxies:
            "\(model.proxyGroups.count) groups"
        case .overrides:
            model.snapshot.overrides.mode.displayName
        case .externalResources:
            "\(model.externalResources.count) files"
        case .logs:
            "\(model.logEntries.count) entries"
        }
    }

    private func subtitle(for section: HomeSection) -> String {
        switch section {
        case .connection:
            model.snapshot.activeProfile?.name ?? "Choose a profile to begin"
        case .profiles:
            "Import local files or refresh online subscriptions"
        case .proxies:
            model.isConnected ? "Select nodes and run delay tests" : "Connect a profile to load proxy groups"
        case .overrides:
            "Routing mode, ports, DNS, and LAN access"
        case .externalResources:
            model.isConnected ? "Edit provider files managed by mihomo" : "Connect a profile to inspect provider files"
        case .logs:
            "App activity and mihomo core events"
        }
    }
}

private struct HomeFeatureCard: View {
    let section: HomeSection
    let value: String
    let subtitle: String
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(section.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isHighlighted ? .green : .secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .liquidGlassCard()
#if os(macOS)
        .help(subtitle)
#endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(value)")
        .accessibilityHint(subtitle)
    }
}

private struct FeatureDetailView: View {
    let section: HomeSection

    var body: some View {
        Group {
            switch section {
            case .connection:
                NavigationStack {
                    DashboardView()
                        .navigationTitle("Connection")
                }
            case .profiles:
                ProfilesView()
            case .proxies:
                ProxiesView()
            case .overrides:
                OverridesView()
            case .externalResources:
                ExternalResourcesView()
            case .logs:
                LogsView()
            }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("connectionSortCriterion") private var connectionSortCriterion = ConnectionSortCriterion.process
    @AppStorage("connectionSortDirection") private var connectionSortDirection = ProxySortDirection.ascending
    @State private var selectedConnection: MihomoConnectionActivity?
    @State private var connectionSearchText = ""
    @State private var showsBackToTopButton = false

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
            Text(model.connectionStatusTitle)
                .font(showsConnections ? .title2.bold() : .largeTitle.bold())
            Text(model.snapshot.activeProfile?.name ?? "Choose a configuration profile to begin")
                .font(showsConnections ? .footnote : .body)
                .foregroundStyle(.secondary)
            if let profile = model.snapshot.activeProfile {
                Button(model.isConnected ? "Disconnect" : "Connect") {
                    if model.isConnected {
                        model.disconnect()
                    } else {
                        Task { await model.connect(profile: profile) }
                    }
                }
                .liquidGlassButton(prominent: true)
                .controlSize(showsConnections ? .regular : .large)
            } else {
                Text("Import a local YAML file or add an online subscription in Profiles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(maxWidth: showsConnections ? 620 : 480)
            HStack(spacing: showsConnections ? 22 : 28) {
                Metric(label: "Mode", value: model.snapshot.overrides.mode.displayName, compact: showsConnections)
                Metric(label: "Profiles", value: "\(model.snapshot.profiles.count)", compact: showsConnections)
                Metric(label: "Groups", value: "\(model.proxyGroups.count)", compact: showsConnections)
            }
        }
    }

    private var connectedDashboard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ConnectionDashboardScrollOffsetKey.self,
                            value: geometry.frame(in: .named("connection-dashboard-scroll")).minY
                        )
                    }
                    .frame(height: 0)
                    .id("connection-dashboard-top")

                    connectionSummary
                        .frame(maxWidth: .infinity)

                    LiveConnectionsView(
                        sortCriterion: $connectionSortCriterion,
                        sortDirection: $connectionSortDirection,
                        selectedConnection: $selectedConnection,
                        searchText: $connectionSearchText
                    )
                }
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .coordinateSpace(name: "connection-dashboard-scroll")
            .onPreferenceChange(ConnectionDashboardScrollOffsetKey.self) { offset in
                let shouldShow = offset < -180
                guard shouldShow != showsBackToTopButton else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
                    showsBackToTopButton = shouldShow
                }
            }
            .searchable(text: $connectionSearchText, prompt: "Search process or destination")
            .overlay(alignment: .bottomTrailing) {
                if showsBackToTopButton {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            proxy.scrollTo("connection-dashboard-top", anchor: .top)
                        }
                    } label: {
                        Label("Back to Top", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 42, height: 42)
                    }
                    .liquidGlassButton()
                    .accessibilityLabel("Back to Top")
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
    let label: String
    let value: String
    var compact = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct LiveConnectionsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sortCriterion: ConnectionSortCriterion
    @Binding var sortDirection: ProxySortDirection
    @Binding var selectedConnection: MihomoConnectionActivity?
    @Binding var searchText: String
    @State private var showingCloseAllConfirmation = false

    private var connections: [MihomoConnectionActivity] {
        model.sortedConnectionActivities(by: sortCriterion, direction: sortDirection)
    }

    private var filteredConnections: [MihomoConnectionActivity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Connections")
                        .font(.headline)
                    Text("Updates every second from mihomo")
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

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    showingCloseAllConfirmation = true
                } label: {
                    Label("Close All", systemImage: "xmark.circle")
                }
                .liquidGlassButton()
                .disabled(connections.isEmpty || model.isClosingAllConnections)
                Spacer()
                Menu {
                    Section("Sort by") {
                        ForEach(ConnectionSortCriterion.allCases) { criterion in
                            Button {
                                sortCriterion = criterion
                                sortDirection = criterion == .speed ? .descending : .ascending
                            } label: {
                                Label(
                                    criterion.displayName,
                                    systemImage: sortCriterion == criterion ? "checkmark" : "circle"
                                )
                            }
                        }
                    }
                    Section("Direction") {
                        ForEach(ProxySortDirection.allCases) { direction in
                            Button {
                                sortDirection = direction
                            } label: {
                                Label(
                                    direction.displayName,
                                    systemImage: sortDirection == direction ? "checkmark" : direction.systemImage
                                )
                            }
                        }
                    }
                } label: {
                    Label(
                        sortCriterion.displayName,
                        systemImage: sortDirection.systemImage
                    )
                        .font(.subheadline.weight(.medium))
                }
                .liquidGlassButton()
            }

            if filteredConnections.isEmpty {
                ContentUnavailableView(
                    connections.isEmpty ? "No Active Connections" : "No Matching Connections",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(connections.isEmpty ? "New traffic will appear here automatically." : "Try a process name, domain, or IP address.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredConnections) { activity in
                        Button {
                            selectedConnection = activity
                        } label: {
                            ConnectionRow(activity: activity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .confirmationDialog(
            "Close All Connections?",
            isPresented: $showingCloseAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close All", role: .destructive) {
                Task { await model.closeAllConnections() }
            }
        } message: {
            Text("This immediately closes every connection managed by mihomo.")
        }
    }
}

private struct ConnectionRow: View {
    let activity: MihomoConnectionActivity

    var body: some View {
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

            Text(activity.connection.routingDescription.isEmpty ? "No matching rule reported" : activity.connection.routingDescription)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.connection.processName), \(byteRate(activity.totalSpeed)), \(activity.connection.routingDescription)")
        .accessibilityHint("Show connection details")
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

            Section("Live Speed") {
                DetailValueRow(label: "Download", value: byteRate(currentActivity.downloadSpeed))
                DetailValueRow(label: "Upload", value: byteRate(currentActivity.uploadSpeed))
                DetailValueRow(label: "Total", value: byteRate(currentActivity.totalSpeed))
            }

            Section("Traffic") {
                DetailValueRow(label: "Downloaded", value: byteCount(connection.download))
                DetailValueRow(label: "Uploaded", value: byteCount(connection.upload))
                if let startedAt = connection.startedAt {
                    DetailValueRow(label: "Started", value: startedAt)
                }
            }

            Section("Routing") {
                DetailValueRow(label: "Rule", value: connection.rule.isEmpty ? "Not reported" : connection.rule)
                DetailValueRow(label: "Rule Payload", value: connection.rulePayload.isEmpty ? "Not reported" : connection.rulePayload)
                if !connection.proxyChainDescription.isEmpty {
                    DetailValueRow(label: "Proxy Chain", value: connection.proxyChainDescription)
                }
                if !connection.providerChainDescription.isEmpty {
                    DetailValueRow(label: "Provider Chain", value: connection.providerChainDescription)
                }
            }

            Section("Connection") {
                DetailValueRow(label: "Protocol", value: [metadata.network, metadata.type].filter { !$0.isEmpty }.joined(separator: " / "))
                DetailValueRow(label: "Source", value: address(metadata.sourceIP, port: metadata.sourcePort))
                DetailValueRow(label: "Destination", value: address(metadata.destinationIP, port: metadata.destinationPort))
                if !metadata.host.isEmpty {
                    DetailValueRow(label: "Host", value: metadata.host)
                }
                if !metadata.remoteDestination.isEmpty {
                    DetailValueRow(label: "Remote Destination", value: metadata.remoteDestination)
                }
                if !metadata.processPath.isEmpty {
                    DetailValueRow(label: "Process Path", value: metadata.processPath)
                }
            }
        }
        .navigationTitle("Connection Details")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .destructive) {
                    Task {
                        if await model.closeConnection(id: activity.id) {
                            dismiss()
                        }
                    }
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .disabled(model.closingConnectionIDs.contains(activity.id))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct DetailValueRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value.isEmpty ? "Not reported" : value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
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

private func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

private func subscriptionSummary(_ subscriptionInfo: MihomoSubscriptionInfo) -> Text {
    var summary = Text("\(byteCount(subscriptionInfo.used)) / \(byteCount(subscriptionInfo.total))")
    if let usageFraction = subscriptionInfo.usageFraction {
        summary = summary + Text(" (\(Int((usageFraction * 100).rounded()))%")
        if let expirationDate = subscriptionInfo.expirationDate {
            summary = summary + Text(", expires ") + Text(expirationDate, format: .dateTime.year().month().day())
        }
        return summary + Text(")")
    }
    if let expirationDate = subscriptionInfo.expirationDate {
        return summary + Text(" (expires ") + Text(expirationDate, format: .dateTime.year().month().day()) + Text(")")
    }
    return summary
}

private func byteRate(_ value: Int64) -> String {
    "\(byteCount(value))/s"
}

private func address(_ host: String, port: String) -> String {
    guard !host.isEmpty else { return "Not reported" }
    guard !port.isEmpty else { return host }
    return "\(host):\(port)"
}

private struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingImporter = false
    @State private var showingRemoteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(model.snapshot.profiles) { profile in
                        ProfileCard(profile: profile)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if model.snapshot.profiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "doc.badge.plus",
                        description: Text("Import a YAML configuration or add a subscription URL.")
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.snapshot.profiles)
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button { showingRemoteSheet = true } label: {
                        Label("Online Profile", systemImage: "link.badge.plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.text, .data],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                Task { await model.addLocalProfile(name: url.deletingPathExtension().lastPathComponent, contents: contents) }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingRemoteSheet) {
            RemoteProfileSheet { name, url, customUserAgent in
                Task { await model.addRemoteProfile(name: name, url: url, customUserAgent: customUserAgent) }
                showingRemoteSheet = false
            }
        }
    }
}

private struct ProfileCard: View {
    @EnvironmentObject private var model: AppModel
    let profile: Profile
    @State private var showingRemoteEditor = false
    @State private var showingProfileOverrideEditor = false

    private var isActive: Bool {
        model.snapshot.activeProfileID == profile.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: profile.source == .remote ? "link" : "doc.text")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(profile.source == .remote ? .indigo : .orange)
                    .frame(width: 38, height: 38)
                    .background(
                        (profile.source == .remote ? Color.indigo : Color.orange).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(profile.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if isActive {
                    Text("ACTIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }

                Menu {
                    if profile.source == .remote {
                        Button {
                            showingRemoteEditor = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) {
                        Task { await model.deleteProfile(profile) }
                    } label: {
                        Label("Delete Profile", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile actions for \(profile.name)")
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(profile.source.displayName.uppercased())
                    Text("Updated \(profile.updatedAt, format: .dateTime.month().day().hour().minute())")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let subscriptionInfo = profile.subscriptionInfo {
                    HStack(spacing: 7) {
                        Label("Subscription", systemImage: "chart.pie.fill")
                        Spacer()
                        subscriptionSummary(subscriptionInfo)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

            }

            HStack(spacing: 10) {
                if profile.source == .remote {
                    Button {
                        Task { await model.refreshProfile(profile) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .liquidGlassButton()
                }

                Button {
                    showingProfileOverrideEditor = true
                } label: {
                    Label("Overrides...", systemImage: "curlybraces.square")
                }
                .liquidGlassButton()

                Spacer()

                Button(isActive && model.isConnected ? "Connected" : "Connect") {
                    Task { await model.connect(profile: profile) }
                }
                .liquidGlassButton(prominent: !isActive || !model.isConnected)
                .disabled(isActive && model.isConnected)
            }
        }
        .padding(14)
        .background(isActive ? Color.green.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isActive ? Color.green.opacity(0.42) : Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .liquidGlassCard()
        .animation(.snappy, value: isActive)
        .sheet(isPresented: $showingRemoteEditor) {
            RemoteProfileSheet(profile: profile) { name, url, customUserAgent in
                Task { await model.updateRemoteProfile(profile, name: name, url: url, customUserAgent: customUserAgent) }
                showingRemoteEditor = false
            }
        }
        .sheet(isPresented: $showingProfileOverrideEditor) {
            ProfileOverrideSheet(profile: profile) { contents, globalOverridesEnabled in
                Task {
                    if globalOverridesEnabled != profile.customOverridesEnabled {
                        await model.setCustomOverridesEnabled(globalOverridesEnabled, for: profile)
                    }
                    if contents != profile.customOverrideYAML {
                        await model.setProfileCustomOverride(contents, for: profile)
                    }
                }
                showingProfileOverrideEditor = false
            }
        }
    }
}

private struct ProfileOverrideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var contents: String
    @State private var globalOverridesEnabled: Bool
    let profile: Profile
    let save: (String, Bool) -> Void

    init(profile: Profile, save: @escaping (String, Bool) -> Void) {
        self.profile = profile
        self.save = save
        _contents = State(initialValue: profile.customOverrideYAML)
        _globalOverridesEnabled = State(initialValue: profile.customOverridesEnabled)
    }

    private var pagePadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 24
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        Image(systemName: "curlybraces.square")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.purple)
                            .frame(width: 58, height: 58)
                            .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile Custom Override")
                                .font(.title3.weight(.semibold))
                            Text("Applied after global custom YAML and before standard overrides.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $globalOverridesEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Global Overrides")
                            Text("Applies global custom YAML when this profile connects. Edit it from the Overrides page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $contents)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                        if contents.isEmpty {
                            Text("# dns!:\n#   enable: false\n# +rules:\n#   - DOMAIN,example.com,DIRECT")
                                .font(.body.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 320)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("key!")
                                .foregroundStyle(.purple)
                            Text("Replace the existing object")
                        }
                        GridRow {
                            Text("+key / key+")
                                .foregroundStyle(.purple)
                            Text("Prepend or append array items")
                        }
                        GridRow {
                            Text("<key>")
                                .foregroundStyle(.purple)
                            Text("Escape a literal plus-prefixed or plus-suffixed key")
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, pagePadding)
                .padding(.vertical, pagePadding)
            }
            .navigationTitle(profile.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(contents, globalOverridesEnabled)
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
#endif
    }
}

private struct RemoteProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var name: String
    @State private var address: String
    @State private var customUserAgent: String
    @FocusState private var focusedField: Field?
    private let profile: Profile?
    let save: (String, URL, String?) -> Void

    init(profile: Profile? = nil, save: @escaping (String, URL, String?) -> Void) {
        self.profile = profile
        self.save = save
        _name = State(initialValue: profile?.name ?? "")
        _address = State(initialValue: profile?.remoteURL?.absoluteString ?? "")
        _customUserAgent = State(initialValue: profile?.customUserAgent ?? "")
    }

    private enum Field {
        case name
        case address
        case customUserAgent
    }

    private var subscriptionURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            return nil
        }
        return url
    }

    private var pagePadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 24
    }

    private var isEditing: Bool { profile != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 58, height: 58)
                            .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isEditing ? "Edit Online Profile" : "Add Online Profile")
                                .font(.title3.weight(.semibold))
                            Text(isEditing ? "Update the subscription details used for future refreshes." : "Import a mihomo subscription directly from its URL.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Subscription URL", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                        TextField("https://example.com/subscription", text: $address)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .address)
                    #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    #endif
                            .padding(14)
                            .liquidGlassCard()

                        if let subscriptionURL {
                            Label(subscriptionURL.host ?? subscriptionURL.absoluteString, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Use a valid HTTP or HTTPS URL.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Profile Name", systemImage: "text.cursor")
                            .font(.subheadline.weight(.semibold))
                        TextField("Optional, uses the subscription host by default", text: $name)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .liquidGlassCard()
                        Text("The name only identifies this profile in Swihomo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Custom User-Agent", systemImage: "network")
                            .font(.subheadline.weight(.semibold))
                        TextField("Optional. Defaults to \(MihomoCoreVersion.userAgent)", text: $customUserAgent)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .customUserAgent)
                            .padding(14)
                            .liquidGlassCard()
                        Text(isEditing ? "Used for future subscription refreshes. Leave empty to use \(MihomoCoreVersion.userAgent)." : "Used for the initial subscription request and every refresh. Leave empty to use \(MihomoCoreVersion.userAgent).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, pagePadding)
                .padding(.vertical, pagePadding)
            }
            .navigationTitle(isEditing ? "Edit Online Profile" : "Online Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save Changes" : "Add Profile") {
                        guard let subscriptionURL else { return }
                        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let userAgent = customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
                        save(
                            profileName.isEmpty ? subscriptionURL.host ?? "Online Profile" : profileName,
                            subscriptionURL,
                            userAgent.isEmpty ? nil : userAgent
                        )
                    }
                    .disabled(subscriptionURL == nil)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 430)
#endif
        .onAppear { focusedField = .address }
    }
}

private struct ProxiesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGroupNames: Set<String> = []
    @AppStorage("proxyGroupSortCriterion") private var groupSortCriterion = ProxyGroupSortCriterion.original
    @AppStorage("proxyGroupSortDirection") private var groupSortDirection = ProxySortDirection.ascending
    @AppStorage("proxyNodeSortCriterion") private var nodeSortCriterion = ProxyNodeSortCriterion.original
    @AppStorage("proxyNodeSortDirection") private var nodeSortDirection = ProxySortDirection.ascending

    var body: some View {
        NavigationStack {
            Group {
                if model.tunnelStatus == .connected {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(model.sortedProxyGroups(by: groupSortCriterion, direction: groupSortDirection)) { group in
                                ProxyGroupSection(
                                    group: group,
                                    isExpanded: expandedGroupNames.contains(group.id),
                                    toggleExpansion: { toggle(group) },
                                    testGroup: { test(group) },
                                    nodeSortCriterion: nodeSortCriterion,
                                    nodeSortDirection: nodeSortDirection
                                )
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .overlay {
                        if model.proxyGroups.isEmpty {
                            ContentUnavailableView(
                                "No Proxy Groups",
                                systemImage: "point.3.connected.trianglepath.dotted",
                                description: Text("Waiting for mihomo's controller to report proxy groups.")
                            )
                            .transition(.opacity)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Connect to Use Proxies",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Connect a profile before viewing proxy groups or selecting nodes.")
                    )
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.proxyGroups)
            .animation(reduceMotion ? nil : .smooth, value: model.delays)
            .navigationTitle("Proxies")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Section("Proxy Group Cards: Sort by") {
                            ForEach(ProxyGroupSortCriterion.allCases) { criterion in
                                Button {
                                    groupSortCriterion = criterion
                                } label: {
                                    Label(
                                        criterion.displayName,
                                        systemImage: groupSortCriterion == criterion ? "checkmark" : "circle"
                                    )
                                }
                            }
                        }
                        Section("Proxy Group Cards: Direction") {
                            ForEach(ProxySortDirection.allCases) { direction in
                                Button {
                                    groupSortDirection = direction
                                } label: {
                                    Label(
                                        direction.displayName,
                                        systemImage: groupSortDirection == direction ? "checkmark" : direction.systemImage
                                    )
                                }
                            }
                        }
                        Section("Nodes Within Groups: Sort by") {
                            ForEach(ProxyNodeSortCriterion.allCases) { criterion in
                                Button {
                                    nodeSortCriterion = criterion
                                } label: {
                                    Label(
                                        criterion.displayName,
                                        systemImage: nodeSortCriterion == criterion ? "checkmark" : "circle"
                                    )
                                }
                            }
                        }
                        Section("Nodes Within Groups: Direction") {
                            ForEach(ProxySortDirection.allCases) { direction in
                                Button {
                                    nodeSortDirection = direction
                                } label: {
                                    Label(
                                        direction.displayName,
                                        systemImage: nodeSortDirection == direction ? "checkmark" : direction.systemImage
                                    )
                                }
                            }
                        }
                    } label: {
                        Label(groupSortCriterion.displayName, systemImage: groupSortDirection.systemImage)
                            .font(.subheadline.weight(.medium))
                    }

                    Button {
                        Task { await model.reloadProxyGroups() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.tunnelStatus != .connected)
                }
            }
            .task(id: model.tunnelStatus == .connected) {
                guard model.tunnelStatus == .connected else { return }
                await model.reloadProxyGroups()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    await model.reloadProxyGroups(showErrors: false)
                }
            }
            .onChange(of: model.proxyGroups.map(\.name)) { _, names in
                synchronizeExpandedGroups(names)
            }
        }
    }

    private func toggle(_ group: MihomoProxyGroup) {
        withAnimation(reduceMotion ? nil : .snappy) {
            if expandedGroupNames.contains(group.id) {
                expandedGroupNames.remove(group.id)
            } else {
                expandedGroupNames.insert(group.id)
            }
        }
    }

    private func test(_ group: MihomoProxyGroup) {
        withAnimation(reduceMotion ? nil : .snappy) {
            _ = expandedGroupNames.insert(group.id)
        }
        Task { await model.testDelays(in: group) }
    }

    private func synchronizeExpandedGroups(_ names: [String]) {
        let availableNames = Set(names)
        guard !availableNames.isEmpty else {
            expandedGroupNames = []
            return
        }
        expandedGroupNames.formIntersection(availableNames)
    }
}

private struct ProxyGroupSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let group: MihomoProxyGroup
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    let testGroup: () -> Void
    let nodeSortCriterion: ProxyNodeSortCriterion
    let nodeSortDirection: ProxySortDirection

    private var usesCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: usesCompactLayout ? 120 : 180,
                maximum: usesCompactLayout ? 180 : 300
            ),
            spacing: usesCompactLayout ? 10 : 12
        )]
    }

    var body: some View {
        let isTesting = model.testingProxyGroupIDs.contains(group.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: toggleExpansion) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name)
                                .font(.headline)
                            Text(group.selected ?? "No selection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(group.candidates.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: testGroup) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test group delay", systemImage: "timer")
                            .labelStyle(.iconOnly)
                    }
                }
                .liquidGlassButton()
                .disabled(isTesting)
                .accessibilityLabel("Test all delays in \(group.name)")
            }

            if isExpanded {
                LazyVGrid(columns: columns, alignment: .leading, spacing: usesCompactLayout ? 10 : 12) {
                    ForEach(
                        model.sortedCandidates(
                            in: group,
                            by: nodeSortCriterion,
                            direction: nodeSortDirection
                        ),
                        id: \.self
                    ) { node in
                        ProxyNodeCard(
                            node: node,
                            group: group,
                            delay: model.delays[node]
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ProxyNodeCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let node: String
    let group: MihomoProxyGroup
    let delay: Int?

    private var isSelected: Bool { group.selected == node }

    private var usesCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 8 : 12) {
            HStack(alignment: .top, spacing: usesCompactLayout ? 6 : 8) {
                Text(node)
                    .font(usesCompactLayout ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                if let delay {
                    Text("\(delay) ms")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(delay < 300 ? .green : .orange)
                } else {
                    Text(usesCompactLayout ? "No result" : "No delay result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.testDelay(for: node) }
                } label: {
                    Label("Test delay", systemImage: "timer")
                        .labelStyle(.iconOnly)
                }
                .liquidGlassButton()
                .controlSize(usesCompactLayout ? .small : .regular)
            }

        }
        .padding(usesCompactLayout ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isSelected ? Color.green.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.green.opacity(0.45) : Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .liquidGlassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isSelected else { return }
            Task { await model.select(node: node, in: group) }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelected ? "Currently selected" : "Select this node")
    }
}

private struct OverridesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draft = ProxyOverrides.default()
    @State private var isControllerSecretVisible = false
    @State private var showingReconnectConfirmation = false

    private var verticalScrollerInset: CGFloat {
#if os(macOS)
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
#else
        0
#endif
    }

    private var usesCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var changesRequireReconnect: Bool {
        let saved = model.snapshot.overrides
        return draft.mixedPort != saved.mixedPort
            || draft.allowLAN != saved.allowLAN
            || draft.ipv6Enabled != saved.ipv6Enabled
            || draft.dnsEnabled != saved.dnsEnabled
            || draft.controllerPort != saved.controllerPort
            || draft.controllerSecret != saved.controllerSecret
            || draft.customYAML != saved.customYAML
    }

    private var saveButton: some View {
        Button {
            let overrides = draft
            let requiresReconnect = changesRequireReconnect
            Task {
                guard await model.saveOverrides(overrides), requiresReconnect, model.tunnelStatus == .connected else { return }
                showingReconnectConfirmation = true
            }
        } label: {
            Label("Save Overrides", systemImage: "checkmark")
        }
        .liquidGlassButton(prominent: true)
        .disabled(draft == model.snapshot.overrides)
    }

    private func portField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number.grouping(.never))
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .onChange(of: value.wrappedValue) { _, port in
                        value.wrappedValue = min(max(port, 1), 65535)
                    }
                Stepper(title, value: value, in: 1...65535)
                    .labelsHidden()
                }
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.pink)
                                .frame(width: 38, height: 38)
                                .background(Color.pink.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Basic Settings")
                                    .font(.headline)
                                Text("Applied after your custom YAML, so these values always take priority.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Routing Mode")
                                .font(.subheadline.weight(.semibold))
                            Picker("Routing Mode", selection: $draft.mode) {
                                ForEach(ProxyMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            HStack {
                                Label("Mihomo Log Level", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Picker("Mihomo Log Level", selection: $draft.logLevel) {
                                    ForEach(MihomoLogLevel.allCases) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Allow LAN connections", isOn: $draft.allowLAN)
                            Toggle("Enable IPv6", isOn: $draft.ipv6Enabled)
                            Toggle("Enable DNS", isOn: $draft.dnsEnabled)
                        }

                        Divider()

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 28) {
                                portField("Mixed Port", value: $draft.mixedPort)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                portField("Controller Port", value: $draft.controllerPort)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                portField("Mixed Port", value: $draft.mixedPort)
                                portField("Controller Port", value: $draft.controllerPort)
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.secondary)
                            if isControllerSecretVisible {
                                TextField("Controller secret", text: $draft.controllerSecret)
                            } else {
                                SecureField("Controller secret", text: $draft.controllerSecret)
                            }
                            Button {
                                isControllerSecretVisible.toggle()
                            } label: {
                                Image(systemName: isControllerSecretVisible ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(isControllerSecretVisible ? "Hide controller secret" : "Show controller secret")
                            .help(isControllerSecretVisible ? "Hide controller secret" : "Show controller secret")
                            .frame(width: 20)
                            .contentShape(Rectangle())
                            .padding(4)
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(18)
                    .liquidGlassCard()

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "curlybraces.square")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.purple)
                                .frame(width: 38, height: 38)
                                .background(Color.purple.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Custom YAML Override")
                                    .font(.headline)
                                Text("Deep-merge profile fields without modifying the source subscription.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Link(destination: URL(string: "https://clashparty.org/docs/guide/override/yaml")!) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open ClashParty YAML override reference")
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $draft.customYAML)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                            if draft.customYAML.isEmpty {
                                Text("# dns!:\n#   enable: false\n# +rules:\n#   - DOMAIN,example.com,DIRECT")
                                    .font(.body.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 320)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("key!")
                                    .foregroundStyle(.purple)
                                Text("Replace the existing object")
                            }
                            GridRow {
                                Text("+key / key+")
                                    .foregroundStyle(.purple)
                                Text("Prepend or append array items")
                            }
                            GridRow {
                                Text("<key>")
                                    .foregroundStyle(.purple)
                                Text("Escape a literal plus-prefixed or plus-suffixed key")
                            }
                        }
                        .font(.caption)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(18)
                    .liquidGlassCard()

                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, usesCompactLayout ? 120 : 88)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if usesCompactLayout {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(draft == model.snapshot.overrides ? "All changes saved" : "Unsaved changes")
                                .font(.subheadline.weight(.semibold))
                            HStack(alignment: .bottom, spacing: 12) {
                                Text("Routing mode and log level update live. Other changes apply after reconnect; invalid YAML prevents mihomo from starting.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                saveButton
                            }
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft == model.snapshot.overrides ? "All changes saved" : "Unsaved changes")
                                    .font(.subheadline.weight(.semibold))
                                Text("Routing mode and log level update live. Other changes apply after reconnect; invalid YAML prevents mihomo from starting.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            saveButton
                        }
                    }
                }
                .padding(14)
                .liquidGlassCard()
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.trailing, verticalScrollerInset)
                .padding(.bottom, 10)
            }
            .navigationTitle("Overrides")
            .onAppear { draft = model.snapshot.overrides }
            .onChange(of: model.snapshot.overrides) { _, overrides in
                draft = overrides
            }
            .confirmationDialog(
                "Reconnect to Apply Changes?",
                isPresented: $showingReconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reconnect") {
                    model.reconnect()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Your saved network, controller, DNS, or custom YAML changes require reconnecting to take effect.")
            }
        }
    }
}

private struct ExternalResourcesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingResource: ExternalResource?
    @State private var importedResource: ExternalResource?
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Provider cache files and the GeoIP or GeoSite databases required by this profile appear here. Update refreshes enabled geodata databases; replace a file, then reconnect to load it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .liquidGlassCard(cornerRadius: 18)

                    ForEach(model.externalResources) { resource in
                        ExternalResourceCard(
                            resource: resource,
                            edit: { editingResource = resource },
                            replace: {
                                importedResource = resource
                                showingImporter = true
                            }
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if model.externalResources.isEmpty {
                    ContentUnavailableView(
                        model.isConnected ? "No Resources" : "Connect to View Resources",
                        systemImage: "externaldrive.connected.to.line.below",
                        description: Text(
                            model.isConnected
                                ? "The active profile has no managed providers or GeoIP and GeoSite rules."
                                : "Connect a profile to inspect the provider files managed by mihomo."
                        )
                    )
                }
            }
            .navigationTitle("Resources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.reloadExternalResources() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isConnected)
                }
            }
            .task { await model.reloadExternalResources() }
            .sheet(item: $editingResource) { resource in
                ExternalResourceEditor(resource: resource)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.text, .data],
                allowsMultipleSelection: false
            ) { result in
                defer { importedResource = nil }
                guard case let .success(urls) = result,
                      let url = urls.first,
                      let resource = importedResource else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let contents = try Data(contentsOf: url)
                    Task { _ = await model.saveExternalResource(resource, contents: contents) }
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ExternalResourceCard: View {
    @EnvironmentObject private var model: AppModel
    let resource: ExternalResource
    let edit: () -> Void
    let replace: () -> Void

    var body: some View {
        let isUpdating = model.updatingExternalResourceIDs.contains(resource.id)
        let tint = switch resource.kind {
        case .proxyProvider: Color.orange
        case .ruleProvider: Color.purple
        case .geoData: Color.teal
        }
        let icon = switch resource.kind {
        case .proxyProvider: "point.3.connected.trianglepath.dotted"
        case .ruleProvider: "list.bullet.rectangle"
        case .geoData: "globe.americas.fill"
        }
        let subscriptionInfo = resource.kind == .proxyProvider ? resource.subscriptionInfo : nil
        VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.name)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(resource.kind.displayName)
                            Text(resource.providerType.uppercased())
                            if let behavior = resource.behavior, !behavior.isEmpty {
                                Text(behavior.uppercased())
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(resource.isPresent ? "READY" : "MISSING")
                        .font(.caption2.bold())
                        .foregroundStyle(resource.isPresent ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if resource.kind == .geoData {
                        Label(
                            resource.isPresent ? "Cached in MihomoCore" : "Not cached yet",
                            systemImage: resource.isPresent ? "internaldrive.fill" : "exclamationmark.triangle"
                        )
                    }

                    HStack(spacing: 8) {
                        Label("Last updated", systemImage: "clock")
                        Spacer()
                        if let updatedAt = resource.updatedAt {
                            Text(updatedAt, format: .dateTime.year().month().day().hour().minute())
                        } else {
                            Text("Unavailable")
                        }
                    }

                    if resource.kind != .geoData, let subscriptionInfo {
                        HStack(spacing: 8) {
                            Label("Subscription", systemImage: "chart.pie.fill")
                            Spacer()
                            subscriptionSummary(subscriptionInfo)
                                .lineLimit(1)
                        }
                    } else if resource.kind != .geoData, let ruleCount = resource.ruleCount {
                        HStack(spacing: 8) {
                            Label("Rules", systemImage: "list.number")
                            Spacer()
                            Text("\(ruleCount) rules")
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack {
                    Button {
                        Task { await model.updateExternalResource(resource) }
                    } label: {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Update", systemImage: "arrow.down.circle")
                                .foregroundStyle(.white)
                        }
                    }
                    .liquidGlassButton(prominent: true)
                    .disabled(!model.isConnected || isUpdating)

                    if resource.kind != .geoData {
                        Button("Edit", action: edit)
                            .liquidGlassButton()
                            .disabled(!resource.isPresent || isUpdating)
                    }
                    Button("Replace", action: replace)
                        .liquidGlassButton()
                        .disabled(isUpdating)
                }
        }
        .padding(14)
        .background(alignment: .topLeading) {
            if let usageFraction = subscriptionInfo?.usageFraction {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(tint.opacity(0.13))
                        .frame(width: geometry.size.width * CGFloat(usageFraction))
                        .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .liquidGlassCard(cornerRadius: 20)
    }
}

private struct ExternalResourceEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let resource: ExternalResource
    @State private var contents = ""
    @State private var originalContents = ""
    @State private var isLoading = true
    @State private var isText = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading \(resource.name)")
                } else if !isText {
                    ContentUnavailableView(
                        "Unsupported Encoding",
                        systemImage: "doc.questionmark",
                        description: Text("This resource is not UTF-8 text. Replace it with a file instead.")
                    )
                } else {
                    TextEditor(text: $contents)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
            .navigationTitle(resource.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.saveExternalResource(resource, contents: Data(contents.utf8)) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isLoading || !isText || contents == originalContents)
                }
            }
            .task {
                guard let data = await model.externalResourceContents(resource) else {
                    isLoading = false
                    return
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    isText = false
                    isLoading = false
                    return
                }
                contents = text
                originalContents = text
                isLoading = false
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
#endif
    }
}

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

    var level: LogLevel? {
        LogLevel(rawValue: rawValue)
    }
}

private struct LogsView: View {
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
            List {
                Section {
                    Picker("Source", selection: $filter) {
                        ForEach(LogFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Level", selection: $levelFilter) {
                        ForEach(LogLevelFilter.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }

                ForEach(entries) { entry in
                    LogEntryRow(entry: entry)
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Logs",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("App and mihomo core events will appear here.")
                    )
                }
            }
            .navigationTitle("Logs")
            .searchable(text: $searchText, prompt: "Search module, message, or level")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearLogsConfirmation = true
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }

                    Button {
                        Task { await model.reloadLogs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isConnected)
                }
            }
            .confirmationDialog(
                "Clear Logs?",
                isPresented: $showingClearLogsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear App Logs", role: .destructive) {
                    Task { await model.clearLogs(source: .app) }
                }
                Button("Clear Core Logs", role: .destructive) {
                    Task { await model.clearLogs(source: .core) }
                }
                Button("Clear All Logs", role: .destructive) {
                    Task { await model.clearLogs() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose which logs to permanently remove.")
            }
            .task { await model.reloadLogs() }
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
                Text(entry.source.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(entry.source == .app ? .blue : .teal)
                Text("[\(entry.module)]")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(entry.level.displayName.uppercased())
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

private extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
