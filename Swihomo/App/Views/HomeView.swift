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

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swihomo")
                        .font(.title.bold())
                    Text("home.controlCenter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                // The connection toggle card doubles as the profiles-page entry; the
                // toggle inside wins its own touches over the link.
                NavigationLink(value: HomeSection.profiles) {
                    connectionToggle
                }
                .buttonStyle(.plain)

                navigationGrid
            }
            .padding()
        }
        .uniformTopScrollEdge()
        .navigationTitle(Text(LocalizedStringKey("navigation.home")))
    }

    private var connectionToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isConnected ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(model.isConnected ? .green : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    (model.isConnected ? Color.green : Color.gray).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            Toggle("common.connect", isOn: connectionBinding)
                .labelsHidden()
                // macOS renders a bare Toggle as a checkbox; this control is a switch.
                .toggleStyle(.switch)
                .disabled(connectionToggleDisabled)
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous))
        .liquidGlassCard(interactive: true)
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

    // Profiles has no grid card of its own; the top toggle card leads there.
    private var gridSections: [HomeSection] {
        HomeSection.allCases.filter { $0 != .profiles }
    }

    @ViewBuilder
    private var navigationGrid: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer {
                navigationGridContent
            }
        } else {
            navigationGridContent
        }
    }

    private var navigationGridContent: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(gridSections) { section in
                NavigationLink(value: section) {
                    HomeFeatureCard(
                        section: section,
                        value: value(for: section),
                        valueKey: valueKey(for: section),
                        subtitle: subtitle(for: section),
                        subtitleKey: subtitleKey(for: section),
                        isHighlighted: section == .connection && model.isConnected
                    )
                }
                .buttonStyle(.plain)
            }
        }
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

private struct HomeFeatureCard: View {
    let section: HomeSection
    let value: String
    let valueKey: String?
    let subtitle: String
    let subtitleKey: String?
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
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous))
        .liquidGlassCard(interactive: true)
        .modifier(HomeFeatureCardHelp(text: subtitle, key: subtitleKey))
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

    var body: some View {
        Group {
            switch section {
            case .connection:
                NavigationStack {
                    DashboardView()
                        .navigationTitle(Text(LocalizedStringKey("navigation.connections")))
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
            case .preference:
                PreferencesView()
            case .about:
                AboutView()
            }
        }
    }
}
