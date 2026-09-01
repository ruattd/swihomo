import SwiftUI

struct ProxiesView: View {
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
                                LocalizedStringKey("proxies.empty"),
                                systemImage: "point.3.connected.trianglepath.dotted",
                                description: Text(LocalizedStringKey("proxies.empty.description"))
                            )
                            .transition(.opacity)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        LocalizedStringKey("proxies.connectToUse"),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(LocalizedStringKey("proxies.connectToUse.description"))
                    )
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.proxyGroups)
            .navigationTitle(Text(LocalizedStringKey("navigation.proxies")))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Section("proxies.sort.groupCards.sortBy") {
                            ForEach(ProxyGroupSortCriterion.allCases) { criterion in
                                Button {
                                    groupSortCriterion = criterion
                                } label: {
                                    Label(
                                        LocalizedStringKey(criterion.localizationKey),
                                        systemImage: groupSortCriterion == criterion ? "checkmark" : "circle"
                                    )
                                }
                            }
                        }
                        Section("proxies.sort.groupCards.direction") {
                            ForEach(ProxySortDirection.allCases) { direction in
                                Button {
                                    groupSortDirection = direction
                                } label: {
                                    Label(
                                        LocalizedStringKey(direction.localizationKey),
                                        systemImage: groupSortDirection == direction ? "checkmark" : direction.systemImage
                                    )
                                }
                            }
                        }
                        Section("proxies.sort.nodes.sortBy") {
                            ForEach(ProxyNodeSortCriterion.allCases) { criterion in
                                Button {
                                    nodeSortCriterion = criterion
                                } label: {
                                    Label(
                                        LocalizedStringKey(criterion.localizationKey),
                                        systemImage: nodeSortCriterion == criterion ? "checkmark" : "circle"
                                    )
                                }
                            }
                        }
                        Section("proxies.sort.nodes.direction") {
                            ForEach(ProxySortDirection.allCases) { direction in
                                Button {
                                    nodeSortDirection = direction
                                } label: {
                                    Label(
                                        LocalizedStringKey(direction.localizationKey),
                                        systemImage: nodeSortDirection == direction ? "checkmark" : direction.systemImage
                                    )
                                }
                            }
                        }
                    } label: {
                        Label(LocalizedStringKey(groupSortCriterion.localizationKey), systemImage: groupSortDirection.systemImage)
                            .font(.subheadline.weight(.medium))
                    }

                    Button {
                        Task { await model.reloadProxyGroups() }
                    } label: {
                        Label("common.refresh", systemImage: "arrow.clockwise")
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

    private var isTesting: Bool { model.testingProxyGroupIDs.contains(group.id) }

    var body: some View {
        GroupBox {
            sectionContent
                .padding(8)
        }
    }

    private var sectionContent: some View {
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
                            if let selected = group.selected {
                                Text(selected)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("common.noSelection")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
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
                        Label("proxies.testGroupDelay", systemImage: "timer")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(isTesting)
                .accessibilityLabel(Text("accessibility.testAllDelays") + Text(verbatim: " \(group.name)"))
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

    private var isTesting: Bool {
        model.testingProxyNodeNames.contains(node)
    }

    var body: some View {
        // Selection and delay test are sibling controls: nesting a Button inside the
        // selection Button makes the inner action unreliable (gate 2 review).
        ZStack(alignment: .bottomTrailing) {
            Button {
                guard !isSelected else { return }
                Task { await model.select(node: node, in: group) }
            } label: {
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
                            Text(LocalizedStringKey(usesCompactLayout ? "proxies.noResult" : "proxies.noDelayResult"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 28)
                    }

                }
                .padding(usesCompactLayout ? 10 : 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    isSelected ? Color.green.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: SurfaceMetrics.rowCornerRadius, style: .continuous)
                )
                .contentCard(cornerRadius: SurfaceMetrics.rowCornerRadius)
                .contentShape(RoundedRectangle(cornerRadius: SurfaceMetrics.rowCornerRadius, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.rowCornerRadius, style: .continuous)
                            .stroke(Color.green.opacity(0.45), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(LocalizedStringKey(isSelected ? "accessibility.currentlySelected" : "accessibility.selectNode"))

            Button {
                Task { await model.testDelay(for: node) }
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("proxies.testDelay", systemImage: "timer")
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(isTesting)
            .controlSize(usesCompactLayout ? .small : .regular)
            .padding(usesCompactLayout ? 10 : 12)
        }
    }
}
