import SwiftUI

enum HomeSection: String, CaseIterable, Hashable, Identifiable {
    case connection
    case profiles
    case proxies
    case overrides
    case externalResources
    case logs
    case preference
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalResources: "Resources"
        case .preference: "Preferences"
        case .about: "About"
        default: rawValue.capitalized
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .connection: "navigation.connections"
        case .profiles: "navigation.profiles"
        case .proxies: "navigation.proxies"
        case .overrides: "navigation.overrides"
        case .externalResources: "navigation.resources"
        case .logs: "navigation.logs"
        case .preference: "navigation.preferences"
        case .about: "navigation.about"
        }
    }

    var icon: String {
        switch self {
        case .connection: "network"
        case .profiles: "doc.on.doc"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .overrides: "slider.horizontal.3"
        case .externalResources: "externaldrive.connected.to.line.below"
        case .logs: "doc.text.magnifyingglass"
        case .preference: "gearshape"
        case .about: "info.circle"
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
        case .preference: .gray
        case .about: .blue
        }
    }
}

#if os(iOS)
/// Routes of the compact tab layout's outer stack. One typed path + one
/// `navigationDestination(for:)` — mixing in `navigationDestination(item:)`
/// anywhere inside a path-based stack crashes SwiftUI with
/// AnyNavigationPath.comparisonTypeMismatch.
enum CompactRoute: Hashable {
    case section(HomeSection)
    case connection(MihomoConnectionActivity)
}

/// Injected by the compact tab layout: pushes a route onto the stack that wraps
/// the TabView, so the tab bar rides the push transition. Nil elsewhere, where
/// plain NavigationLinks / nested stacks handle navigation.
private struct PushCompactRouteKey: EnvironmentKey {
    static let defaultValue: ((CompactRoute) -> Void)? = nil
}

extension EnvironmentValues {
    var pushCompactRoute: ((CompactRoute) -> Void)? {
        get { self[PushCompactRouteKey.self] }
        set { self[PushCompactRouteKey.self] = newValue }
    }
}
#endif

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pushCompactRoute) private var pushCompactRoute
    #endif
    // Drives the toggle card's press bounce on the whole glass surface; the switch
    // sits outside the link and never triggers it.
    @State private var toggleCardContracted = false
    #if os(macOS)
    // macOS navigates by driving the detail column's selection: pushing links
    // inside the sidebar column would tear down this whole grid on every switch.
    @Binding var activeSection: HomeSection

    init(activeSection: Binding<HomeSection>) {
        _activeSection = activeSection
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // macOS keeps the in-content title header; iOS uses the navigation title.
                #if os(macOS)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swihomo")
                        .font(.title.bold())
                    Text("home.controlCenter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                #endif

                connectionToggle

                navigationGrid
            }
            .padding()
            // macOS scroll indicators overlay the grid cards; reserve their lane.
            #if os(macOS)
            .padding(.trailing, 4)
            #endif
        }
        .uniformTopScrollEdge()
        #if os(macOS)
        .navigationTitle(Text(LocalizedStringKey("navigation.home")))
        #else
        .navigationTitle("Swihomo")
        #endif
    }

    // The card is the profiles-page entry, but the switch sits OUTSIDE the link —
    // toggling it must not trigger the card's press animation.
    private var connectionToggle: some View {
        HStack(spacing: 12) {
            homeNavigation(to: .profiles, contracted: $toggleCardContracted) {
                HStack(spacing: 12) {
                    // Sized like HomeBannerRow so the switch card and the
                    // connections banner align when stacked.
                    Image(systemName: model.isConnected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(model.isConnected ? .green : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            (model.isConnected ? Color.green : Color.gray).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(model.connectionStatusLocalizationKey))
                            .font(.headline)
                        Text(model.snapshot.activeProfile?.name ?? String(localized: "home.chooseProfile"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }

            Toggle("common.connect", isOn: connectionBinding)
                .labelsHidden()
                // macOS renders a bare Toggle as a checkbox; this control is a switch.
                .toggleStyle(.switch)
                .disabled(connectionToggleDisabled)
        }
        .padding(16)
        // Scale must wrap the glass surface, not just its content.
        .liquidGlassCard(interactive: true)
        .scaleEffect(toggleCardContracted ? 0.96 : 1)
    }

    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { model.isConnected },
            set: { on in
                if on {
                    guard let profile = model.snapshot.activeProfile else { return }
                    Task { await model.connect(profile: profile) }
                } else {
                    model.disconnect()
                }
            }
        )
    }

    // Disabled mid-transition (connecting/disconnecting/reasserting) and with no profile.
    private var connectionToggleDisabled: Bool {
        model.snapshot.activeProfile == nil
            || model.tunnelStatus == .connecting
            || model.tunnelStatus == .disconnecting
            || model.tunnelStatus == .reasserting
    }

    /// iPhone compact layout (iOS 18+) uses bottom tabs: proxies becomes a tab,
    /// connections a banner row, and preferences/about leave the home grid
    /// entirely. Older iOS keeps the traditional full home even when narrow.
    private var compactHome: Bool {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            return horizontalSizeClass == .compact
        }
        return false
        #else
        false
        #endif
    }

    // Profiles has no grid card of its own (the top toggle card leads there);
    // preferences/about render as wide banners below the grid instead.
    private var gridSections: [HomeSection] {
        if compactHome { return [.overrides, .externalResources, .logs] }
        return [.proxies, .connection, .overrides, .externalResources, .logs]
    }

    private var bannerSections: [HomeSection] {
        if compactHome { return [] }
        return [.preference, .about]
    }

    @ViewBuilder
    private var navigationGrid: some View {
        // GlassEffectContainer merges the cards' glass on iOS; on macOS it swallows the
        // interactive glass press effect, so the cards stay ungrouped there.
        #if os(macOS)
        navigationGridContent
        #else
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                navigationGridContent
            }
        } else {
            navigationGridContent
        }
        #endif
    }

    private var navigationGridContent: some View {
        VStack(spacing: 12) {
            if compactHome {
                homeNavigation(to: .connection) {
                    HomeBannerRow(
                        section: .connection,
                        subtitle: subtitle(for: .connection),
                        subtitleKey: subtitleKey(for: .connection)
                    )
                }
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(gridSections) { section in
                    homeNavigation(to: section) {
                        HomeFeatureCard(
                            section: section,
                            value: value(for: section),
                            valueKey: valueKey(for: section),
                            subtitle: subtitle(for: section),
                            subtitleKey: subtitleKey(for: section),
                            helpKey: section == .connection ? "home.connectionsHint" : subtitleKey(for: section),
                            isHighlighted: section == .connection && model.isConnected
                        )
                    }
                }
            }

            ForEach(bannerSections) { section in
                homeNavigation(to: section) {
                    HomeBannerRow(
                        section: section,
                        subtitle: subtitle(for: section),
                        subtitleKey: subtitleKey(for: section)
                    )
                }
            }
        }
    }

    // iOS pushes destinations onto the enclosing stack; macOS drives the detail
    // column's selection instead, so this grid survives page switches.
    @ViewBuilder
    private func homeNavigation<Label: View>(
        to section: HomeSection,
        contracted: Binding<Bool>? = nil,
        @ViewBuilder label: () -> Label
    ) -> some View {
        #if os(macOS)
        Button {
            // The fade lives inside DetailPageHost (layer-driven); no SwiftUI
            // transaction needed here.
            activeSection = section
        } label: {
            label()
        }
        .buttonStyle(NavigationCardButtonStyle(contracted: contracted))
        #else
        if let pushCompactRoute {
            // Compact tab layout: push onto the outer stack covering the TabView.
            Button {
                pushCompactRoute(.section(section))
            } label: {
                label()
            }
            .buttonStyle(NavigationCardButtonStyle(contracted: contracted))
        } else {
            NavigationLink {
                FeatureDetailView(section: section)
            } label: {
                label()
            }
            .buttonStyle(NavigationCardButtonStyle(contracted: contracted))
        }
        #endif
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
        case .preference:
            "App settings"
        case .about:
            appVersion
        }
    }

    private func valueKey(for section: HomeSection) -> String? {
        switch section {
        case .connection:
            model.connectionStatusLocalizationKey
        case .overrides:
            model.snapshot.overrides.mode.localizationKey
        case .preference:
            "home.appSettings"
        default:
            nil
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
        case .preference:
            "Configure Swihomo for this device"
        case .about:
            "App details and open-source licenses"
        }
    }

    private func subtitleKey(for section: HomeSection) -> String? {
        switch section {
        case .connection:
            model.snapshot.activeProfile == nil ? "home.chooseProfile" : nil
        case .profiles:
            "home.profilesSubtitle"
        case .proxies:
            model.isConnected ? "home.proxies.connectedSubtitle" : "home.proxies.disconnectedSubtitle"
        case .overrides:
            "home.overridesSubtitle"
        case .externalResources:
            model.isConnected ? "home.resources.connectedSubtitle" : "home.resources.disconnectedSubtitle"
        case .logs:
            "home.logsSubtitle"
        case .preference:
            "home.preferencesSubtitle"
        case .about:
            "home.aboutSubtitle"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// Equatable: navigation-triggered publishes (page loads firing on appear) must not
// re-render the glass grid mid-transition.
private struct HomeFeatureCard: View, Equatable {
    let section: HomeSection
    let value: String
    let valueKey: String?
    let subtitle: String
    let subtitleKey: String?
    let helpKey: String?
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(section.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(section.titleKey)
                    .font(.subheadline.weight(.semibold))
                if let valueKey {
                    Text(LocalizedStringKey(valueKey))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isHighlighted ? .green : .secondary)
                } else {
                    Text(value)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isHighlighted ? .green : .secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous))
        .liquidGlassCard(interactive: true)
        .modifier(HomeFeatureCardHelp(text: subtitle, key: helpKey ?? subtitleKey))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(section.titleKey) + Text(verbatim: ", ") + valueText)
        .accessibilityHint(subtitle)
    }

    private var valueText: Text {
        if let valueKey {
            Text(LocalizedStringKey(valueKey))
        } else {
            Text(verbatim: value)
        }
    }
}

// Full-width banner variant of the feature card, for utility sections under the grid.
private struct HomeBannerRow: View, Equatable {
    let section: HomeSection
    let subtitle: String
    let subtitleKey: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.icon)
                .font(.title.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(section.tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .font(.headline)
                if let subtitleKey {
                    Text(LocalizedStringKey(subtitleKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        // iOS keeps the enlarged touch target; macOS sidebar banners stay tight.
        #if os(macOS)
        .padding(12)
        #else
        .padding(16)
        #endif
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous))
        .liquidGlassCard(interactive: true)
        .modifier(HomeFeatureCardHelp(text: subtitle, key: subtitleKey))
        .accessibilityElement(children: .combine)
        .accessibilityHint(subtitle)
    }
}

private struct HomeFeatureCardHelp: ViewModifier {
    let text: String
    let key: String?

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if let key {
            content.help(LocalizedStringKey(key))
        } else {
            content.help(text)
        }
#else
        content
#endif
    }
}

struct FeatureDetailView: View {
    let section: HomeSection
    #if os(iOS)
    @Environment(\.pushCompactRoute) private var pushCompactRoute
    #endif

    var body: some View {
        Group {
            switch section {
            case .connection:
                #if os(iOS)
                if pushCompactRoute != nil {
                    // Compact tab layout: the outer stack is live here, and a
                    // nested NavigationStack inside pushed content never becomes
                    // a real stack — drill-ins replace the page outright (no push
                    // animation, back pops straight past this page). Register the
                    // connection detail on the outer stack instead.
                    DashboardView()
                        .detailPageTitle("navigation.connections")
                } else {
                    NavigationStack {
                        DashboardView()
                            .detailPageTitle("navigation.connections")
                    }
                }
                #else
                NavigationStack {
                    DashboardView()
                        .detailPageTitle("navigation.connections")
                }
                #endif
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
            case .preference:
                PreferencesView()
            case .about:
                AboutView()
            }
        }
    }
}
