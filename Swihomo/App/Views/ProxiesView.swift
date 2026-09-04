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
        PageNavigationStack {
            Group {
                if model.tunnelStatus == .connected {
                    // ScrollView, not List: expansion animates row height, and List rows
                    // hand height changes to UICollectionView, which fights SwiftUI's
                    // layout animation (double animation). Laziness that matters — the
                    // node grids — stays lazy inside each card via LazyVGrid.
                    ScrollView {
                        LazyVStack(spacing: 14) {
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
                    }
                    .uniformTopScrollEdge()
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
                    ContentUnavailableView {
                        Label {
                            Text(LocalizedStringKey("proxies.connectToUse"))
                        } icon: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .frame(height: 40)
                        }
                    } description: {
                        Text(LocalizedStringKey("proxies.connectToUse.description"))
                    }
                }
            }
            .detailPageTitle("navigation.proxies")
            #if os(macOS)
            // Chrome is hoisted to the detail container; per-page .toolbar inside
            // nested hosting controllers collides in the shared window toolbar.
            .background(ChromeProvider(
                section: .proxies,
                toolbar: { AnyView(ProxiesToolbarContent()) }
            ))
            #else
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ProxiesToolbarContent()
                }
            }
            #endif
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
        // Fixed-duration ease: springs overshoot proportionally to distance, so tall
        // cards rebound hard when collapsing. easeInOut has no overshoot at any height.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if expandedGroupNames.contains(group.id) {
                expandedGroupNames.remove(group.id)
            } else if UserDefaults.standard.bool(forKey: "autoCollapseProxyGroups") {
                expandedGroupNames = [group.id]
            } else {
                expandedGroupNames.insert(group.id)
            }
        }
    }

    private func test(_ group: MihomoProxyGroup) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if UserDefaults.standard.bool(forKey: "autoCollapseProxyGroups") {
                expandedGroupNames = [group.id]
            } else {
                _ = expandedGroupNames.insert(group.id)
            }
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

// Toolbar content for the proxies page, rendered by the container on macOS (via
// ChromeProvider) and in-page on iOS. Declares its own AppStorage so it stays
// reactive in whichever view graph renders it.
private struct ProxiesToolbarContent: View {
    @AppStorage("proxyGroupSortCriterion") private var groupSortCriterion = ProxyGroupSortCriterion.original
    @AppStorage("proxyGroupSortDirection") private var groupSortDirection = ProxySortDirection.ascending
    @AppStorage("proxyNodeSortCriterion") private var nodeSortCriterion = ProxyNodeSortCriterion.original
    @AppStorage("proxyNodeSortDirection") private var nodeSortDirection = ProxySortDirection.ascending

    var body: some View {
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
        sectionContent
            .padding(12)
            .contentCard()
            // Keep collapsing content inside the card during the height animation.
            .clipShape(RoundedRectangle(cornerRadius: SurfaceMetrics.boxCornerRadius, style: .continuous))
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
                .liquidGlassButton()
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

    private func selectNode() {
        guard !isSelected else { return }
        Task { await model.select(node: node, in: group) }
    }

    var body: some View {
        // Parallel two-row layout; the container owns selection taps for the whole card
        // and the test capsule — a parallel child control — intercepts its own touches.
        // (No overlay/nesting: those made the capsule's action unreliable.)
        VStack(alignment: .leading, spacing: usesCompactLayout ? 8 : 12) {
            HStack(alignment: .top, spacing: usesCompactLayout ? 6 : 8) {
                Text(node)
                    .font(usesCompactLayout ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    // Match the title font: the default body-sized symbol is taller
                    // than the text line, making selected cards higher than the rest.
                    Image(systemName: "checkmark.circle.fill")
                        .font(usesCompactLayout ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Group {
                    if let delay {
                        Text("\(delay) ms")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(delay < 300 ? .green : .orange)
                    } else if let failure = model.failedDelayTests[node] {
                        Text(failure == .timeout ? "proxies.testTimeout" : "proxies.testFailed")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(LocalizedStringKey(usesCompactLayout ? "proxies.noResult" : "proxies.noDelayResult"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottomLeading)

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
                .liquidGlassButton()
                .disabled(isTesting)
                .controlSize(.small)
            }
        }
        .padding(usesCompactLayout ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectNode)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(LocalizedStringKey(isSelected ? "accessibility.currentlySelected" : "accessibility.selectNode"))
        .background(
            isSelected ? Color.green.opacity(0.2) : Color.clear,
            in: RoundedRectangle(cornerRadius: SurfaceMetrics.rowCornerRadius, style: .continuous)
        )
        .contentCard(cornerRadius: SurfaceMetrics.rowCornerRadius)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SurfaceMetrics.rowCornerRadius, style: .continuous)
                    .stroke(Color.green.opacity(0.45), lineWidth: 1)
            }
        }
        // Scoped to isSelected only — animating on model-wide values would replay on
        // every 2s group poll.
        .animation(.easeInOut(duration: 0.25), value: isSelected)
    }
}
