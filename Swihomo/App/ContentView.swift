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
                    .lineLimit(2)
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: model.isConnected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 72))
                .foregroundStyle(model.isConnected ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, value: model.isConnected)
            Text(model.connectionStatusTitle)
                .font(.largeTitle.bold())
            Text(model.snapshot.activeProfile?.name ?? "Choose a configuration profile to begin")
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
                .controlSize(.large)
            } else {
                Text("Import a local YAML file or add an online subscription in Profiles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(maxWidth: 480)
            HStack(spacing: 28) {
                Metric(label: "Mode", value: model.snapshot.overrides.mode.displayName)
                Metric(label: "Profiles", value: "\(model.snapshot.profiles.count)")
                Metric(label: "Groups", value: "\(model.proxyGroups.count)")
            }
            Spacer()
        }
        .padding()
        .animation(reduceMotion ? nil : .bouncy, value: model.isConnected)
        .animation(reduceMotion ? nil : .snappy, value: model.snapshot.activeProfileID)
    }

}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
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

                if let remoteURL = profile.remoteURL {
                    Text(remoteURL.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
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
    }
}

private struct RemoteProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var name = ""
    @State private var address = ""
    @State private var customUserAgent = ""
    @FocusState private var focusedField: Field?
    let save: (String, URL, String?) -> Void

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
                            Text("Add Online Profile")
                                .font(.title3.weight(.semibold))
                            Text("Import a mihomo subscription directly from its URL.")
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
                        Text("Used for the initial subscription request and every refresh. Leave empty to use \(MihomoCoreVersion.userAgent).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, pagePadding)
                .padding(.vertical, pagePadding)
            }
            .navigationTitle("Online Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Profile") {
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var expandedGroupNames: Set<String> = []
    @State private var groupSortCriterion = ProxyGroupSortCriterion.original
    @State private var groupSortDirection = ProxySortDirection.ascending
    @State private var nodeSortCriterion = ProxyNodeSortCriterion.original
    @State private var nodeSortDirection = ProxySortDirection.ascending
    @State private var isShowingSortOptions = false

    private var usesCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

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
                    if usesCompactLayout {
                        Button {
                            isShowingSortOptions = true
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    } else {
                        Menu {
                            Section("Proxy Group Cards") {
                                Picker("Order", selection: $groupSortCriterion) {
                                    ForEach(ProxyGroupSortCriterion.allCases) { criterion in
                                        Text(criterion.displayName).tag(criterion)
                                    }
                                }
                                Picker("Direction", selection: $groupSortDirection) {
                                    ForEach(ProxySortDirection.allCases) { direction in
                                        Label(direction.displayName, systemImage: direction.systemImage).tag(direction)
                                    }
                                }
                            }
                            Section("Nodes Within Groups") {
                                Picker("Order", selection: $nodeSortCriterion) {
                                    ForEach(ProxyNodeSortCriterion.allCases) { criterion in
                                        Text(criterion.displayName).tag(criterion)
                                    }
                                }
                                Picker("Direction", selection: $nodeSortDirection) {
                                    ForEach(ProxySortDirection.allCases) { direction in
                                        Label(direction.displayName, systemImage: direction.systemImage).tag(direction)
                                    }
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
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
            .sheet(isPresented: $isShowingSortOptions) {
                ProxySortOptionsSheet(
                    groupSortCriterion: $groupSortCriterion,
                    groupSortDirection: $groupSortDirection,
                    nodeSortCriterion: $nodeSortCriterion,
                    nodeSortDirection: $nodeSortDirection
                )
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

private struct ProxySortOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var groupSortCriterion: ProxyGroupSortCriterion
    @Binding var groupSortDirection: ProxySortDirection
    @Binding var nodeSortCriterion: ProxyNodeSortCriterion
    @Binding var nodeSortDirection: ProxySortDirection

    var body: some View {
        NavigationStack {
            Form {
                Section("Proxy Group Cards") {
                    Picker("Order", selection: $groupSortCriterion) {
                        ForEach(ProxyGroupSortCriterion.allCases) { criterion in
                            Text(criterion.displayName).tag(criterion)
                        }
                    }
                    Picker("Direction", selection: $groupSortDirection) {
                        ForEach(ProxySortDirection.allCases) { direction in
                            Label(direction.displayName, systemImage: direction.systemImage).tag(direction)
                        }
                    }
                }

                Section("Nodes Within Every Group") {
                    Picker("Order", selection: $nodeSortCriterion) {
                        ForEach(ProxyNodeSortCriterion.allCases) { criterion in
                            Text(criterion.displayName).tag(criterion)
                        }
                    }
                    Picker("Direction", selection: $nodeSortDirection) {
                        ForEach(ProxySortDirection.allCases) { direction in
                            Label(direction.displayName, systemImage: direction.systemImage).tag(direction)
                        }
                    }
                }
            }
            .navigationTitle("Sort Proxies")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
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

    private var saveButton: some View {
        Button {
            Task { await model.saveOverrides(draft) }
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
                                Text("Log level updates live. Other changes apply after reconnect; invalid YAML prevents mihomo from starting.")
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
                                Text("Log level updates live. Other changes apply after reconnect; invalid YAML prevents mihomo from starting.")
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
            List {
                Section {
                    Text("Only file and HTTP providers with a mihomo-managed cache file appear here. Save changes, then use Update to load them into the running core.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.externalResources) { resource in
                    ExternalResourceRow(
                        resource: resource,
                        edit: { editingResource = resource },
                        replace: {
                            importedResource = resource
                            showingImporter = true
                        }
                    )
                }
            }
            .overlay {
                if model.externalResources.isEmpty {
                    ContentUnavailableView(
                        model.isConnected ? "No Resources" : "Connect to View Resources",
                        systemImage: "externaldrive.connected.to.line.below",
                        description: Text(
                            model.isConnected
                                ? "The active profile has no file or HTTP proxy and rule providers."
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

private struct ExternalResourceRow: View {
    @EnvironmentObject private var model: AppModel
    let resource: ExternalResource
    let edit: () -> Void
    let replace: () -> Void

    var body: some View {
        let isUpdating = model.updatingExternalResourceIDs.contains(resource.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: resource.kind == .proxyProvider ? "point.3.connected.trianglepath.dotted" : "list.bullet.rectangle")
                    .foregroundStyle(resource.kind == .proxyProvider ? .orange : .purple)
                Text(resource.name)
                    .fontWeight(.medium)
                Spacer()
                Text(resource.isPresent ? "READY" : "MISSING")
                    .font(.caption2.bold())
                    .foregroundStyle(resource.isPresent ? .green : .orange)
            }

            HStack(spacing: 6) {
                Text(resource.kind.displayName)
                Text(resource.providerType.uppercased())
                if let behavior = resource.behavior, !behavior.isEmpty {
                    Text(behavior.uppercased())
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Text(resource.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let url = resource.url, !url.isEmpty {
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

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
                Button("Edit", action: edit)
                    .liquidGlassButton()
                    .disabled(!resource.isPresent || isUpdating)
                Button("Replace", action: replace)
                    .liquidGlassButton()
                    .disabled(isUpdating)
            }
        }
        .padding(.vertical, 4)
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
        .frame(minWidth: 520, minHeight: 420)
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.reloadLogs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isConnected)
                }
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
