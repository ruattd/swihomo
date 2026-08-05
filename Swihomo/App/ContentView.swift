import SwiftUI
import UniformTypeIdentifiers
import CodeEditorView
import LanguageSupport
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appTheme") private var selectedTheme = AppTheme.system.rawValue
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    #if os(macOS)
    @AppStorage("hidesDockIcon") private var hidesDockIcon = false
    #endif

    private var preferredColorScheme: ColorScheme? {
        AppTheme(rawValue: selectedTheme)?.colorScheme
    }

    var body: some View {
        NavigationSplitView {
            HomeView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 460)
                #if os(macOS)
                .frame(minWidth: 280)
                #endif
                .navigationDestination(for: HomeSection.self) { section in
                    FeatureDetailView(section: section)
                }
        } detail: {
            FeatureDetailView(section: .connection)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
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
#if os(macOS)
        .onAppear {
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
            DockIconVisibility.activateWindowIfNeeded(
                showsMenuBar: showsMenuBar,
                hidesDockIcon: hidesDockIcon
            )
        }
        .onChange(of: showsMenuBar) { _, _ in
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
        }
        .onChange(of: hidesDockIcon) { _, _ in
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
        }
#endif
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
                Text("accessibility.requestFailed")
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
            .accessibilityLabel("accessibility.dismissError")
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

#if os(macOS)
private enum DockIconVisibility {
    static func update(showsMenuBar: Bool, hidesDockIcon: Bool) {
        NSApplication.shared.setActivationPolicy(showsMenuBar && hidesDockIcon ? .accessory : .regular)
    }

    static func activateWindowIfNeeded(showsMenuBar: Bool, hidesDockIcon: Bool) {
        guard showsMenuBar && hidesDockIcon else { return }

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        }
    }
}
#endif

private enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .light: "preferences.appearance.light"
        case .dark: "preferences.appearance.dark"
        case .system: "preferences.appearance.system"
        }
    }

    var subtitle: String {
        switch self {
        case .light: "Always light"
        case .dark: "Always dark"
        case .system: "Match device"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .light: "preferences.appearance.lightDescription"
        case .dark: "preferences.appearance.darkDescription"
        case .system: "preferences.appearance.systemDescription"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

private enum HomeSection: String, CaseIterable, Hashable, Identifiable {
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
        case .connection: "navigation.connection"
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
        case .connection: "bolt.shield"
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

private struct HomeView: View {
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
            .padding()
        }
        .navigationTitle(Text(LocalizedStringKey("navigation.home")))
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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

private struct FeatureDetailView: View {
    let section: HomeSection

    var body: some View {
        Group {
            switch section {
            case .connection:
                NavigationStack {
                    DashboardView()
                        .navigationTitle(Text(LocalizedStringKey("navigation.connection")))
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

private struct PreferencesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appTheme") private var selectedTheme = AppTheme.system.rawValue
    @State private var systemThemeResetID = UUID()
    @AppStorage("automaticallyReclaimsMemory") private var automaticallyReclaimsMemory = false
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    @AppStorage("menuBarDisplay") private var menuBarDisplay = "iconAndSpeed"
    @AppStorage("appLogLevel") private var appLogLevel = LogLevel.info.rawValue
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage("packetTunnelBypassesPrivateNetworks") private var packetTunnelBypassesPrivateNetworks = false
    @AppStorage("packetTunnelBypassCIDRs") private var packetTunnelBypassCIDRs = ""
    @AppStorage("packetTunnelMTU") private var packetTunnelMTU = 1500
    @AppStorage("packetTunnelCustomDNSServers") private var packetTunnelCustomDNSServers = ""
    @AppStorage("packetTunnelIPv6Enabled") private var packetTunnelIPv6Enabled = true
    #if os(macOS)
    @AppStorage("hidesDockIcon") private var hidesDockIcon = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("preferences.appearance.title")
                            .font(.title2.bold())
                        Text("preferences.appearance.description")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if horizontalSizeClass == .compact {
                        Picker("preferences.appearance.title", selection: themeSelection) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.titleKey).tag(theme.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                themeOptions
                            }

                            VStack(spacing: 12) {
                                themeOptions
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassCard(cornerRadius: 20)

#if os(macOS)
                menuBarSettings
#endif

                applicationSettings
                packetTunnelSettings
                memoryManagementSettings
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(Text(LocalizedStringKey("navigation.preferences")))
    }

    private var memoryManagementSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("preferences.experimental", systemImage: "flask")
                .font(.title3.weight(.semibold))

            Toggle("preferences.experimental.autoReclaimMemory", isOn: $automaticallyReclaimsMemory)

            Text("preferences.experimental.autoReclaimMemory.description")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var applicationSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("preferences.application.title", systemImage: "app.badge")
                .font(.title3.weight(.semibold))

            HStack {
                Text("preferences.application.logLevel")
                Spacer()
                Picker("preferences.application.logLevel", selection: $appLogLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(LocalizedStringKey(level.localizationKey)).tag(level.rawValue)
                    }
                }
                .labelsHidden()
            }

            Text("preferences.application.logLevel.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("preferences.application.language")
                Spacer()
                Picker("preferences.application.language", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        languageLabel(for: language).tag(language.rawValue)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private func languageLabel(for language: AppLanguage) -> some View {
        if let titleKey = language.titleKey {
            Text(titleKey)
        } else if let endonym = language.endonym {
            Text(verbatim: endonym)
        }
    }

    private var packetTunnelSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("preferences.packetTunnel.title", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.semibold))

            HStack {
                Text(verbatim: SharedText.mtu)
                Spacer()
                Picker(selection: $packetTunnelMTU) {
                    ForEach([1280, 1360, 1420, 1500], id: \.self) { mtu in
                        Text("\(mtu)").tag(mtu)
                    }
                } label: {
                    Text(verbatim: SharedText.mtu)
                }
                .labelsHidden()
            }

            Toggle("preferences.packetTunnel.routeIPv6", isOn: $packetTunnelIPv6Enabled)

            Text("preferences.packetTunnel.routeIPv6.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("preferences.packetTunnel.customDNS")
                .font(.subheadline.weight(.medium))

            MultilineCodeEditor(text: $packetTunnelCustomDNSServers, minHeight: 100)

            Text("preferences.packetTunnel.customDNS.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("preferences.packetTunnel.bypassLocalNetworks", isOn: $packetTunnelBypassesPrivateNetworks)

            Text("preferences.packetTunnel.bypassLocalNetworks.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("preferences.packetTunnel.bypassIPRanges")
                .font(.subheadline.weight(.medium))

            MultilineCodeEditor(text: $packetTunnelBypassCIDRs, minHeight: 120)

            Text("preferences.packetTunnel.bypassIPRanges.description")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var themeOptions: some View {
        ForEach(AppTheme.allCases) { theme in
            ThemeOptionCard(
                theme: theme,
                isSelected: selectedTheme == theme.rawValue
            ) {
                selectTheme(theme)
            }
        }
    }

    private var themeSelection: Binding<String> {
        Binding(
            get: { self.selectedTheme },
            set: { newValue in
                guard let theme = AppTheme(rawValue: newValue) else { return }
                self.selectTheme(theme)
            }
        )
    }

    private func selectTheme(_ theme: AppTheme) {
        #if os(macOS)
        let resetID = UUID()
        systemThemeResetID = resetID

        guard theme == .system, selectedTheme != AppTheme.system.rawValue else {
            selectedTheme = theme.rawValue
            return
        }

        // Preserve the current system appearance while SwiftUI releases the explicit override.
        selectedTheme = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            ? AppTheme.dark.rawValue
            : AppTheme.light.rawValue
        DispatchQueue.main.async {
            guard systemThemeResetID == resetID else { return }
            selectedTheme = AppTheme.system.rawValue
        }
        #else
        selectedTheme = theme.rawValue
        #endif
    }

#if os(macOS)
    private var menuBarSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("preferences.menuBar.title", systemImage: "menubar.rectangle")
                .font(.title3.weight(.semibold))

            Toggle("preferences.menuBar.show", isOn: $showsMenuBar)

            Divider()

            Picker("preferences.menuBar.display", selection: $menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases) { display in
                    Text(display.titleKey).tag(display.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!showsMenuBar)

            if menuBarDisplay == MenuBarDisplay.icon.rawValue {
                Text("preferences.menuBar.display.iconOnlyDescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("preferences.menuBar.hideDockIcon", isOn: $hidesDockIcon)
                .disabled(!showsMenuBar)

            if !showsMenuBar {
                Text("preferences.menuBar.hideDockIcon.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }
#endif
}

private struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    appIcon
                        .frame(width: 96, height: 96)

                    Text("Swihomo")
                        .font(.title.bold())
                    Text("about.subtitle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    AboutDetailRow(title: "about.version", value: appVersion)
                    Divider()
                    AboutDetailRow(title: "about.build", value: buildNumber)
                    Divider()
                    AboutDetailRow(title: "about.mihomoCore", value: MihomoCoreVersion.version)
                    Divider()
                    AboutDetailRow(title: "about.license", value: "AGPL-3.0")
                }
                .liquidGlassCard(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("about.openSource")
                        .font(.headline)
                    Text("about.openSource.description")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link("about.openSource.viewSwihomo", destination: URL(string: "https://github.com/ruattd/swihomo")!)
                    Link("about.openSource.viewMihomo", destination: URL(string: "https://github.com/MetaCubeX/mihomo")!)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .liquidGlassCard(cornerRadius: 20)
            }
            .padding(20)
            .frame(maxWidth: 560)
        }
        .navigationTitle(Text(LocalizedStringKey("navigation.about")))
    }

    @ViewBuilder
    private var appIcon: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
        #else
        Image(uiImage: UIImage(named: "AppIcon60x60") ?? UIImage())
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }
}

private struct AboutDetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}

private struct ThemeOptionCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                preview
                    .frame(height: 96)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(theme.titleKey)
                            .font(.headline)
                        Text(theme.subtitleKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(minWidth: 144, maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .liquidGlassCard(cornerRadius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.titleKey) + Text("preferences.appearance.labelSuffix"))
        .accessibilityValue(Text(LocalizedStringKey(isSelected ? "common.selected" : "common.notSelected")))
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(previewBackground)

            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(previewText)
                        .frame(width: 54, height: 7)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(previewCard)
                    .frame(height: 36)
            }
            .padding(12)
        }
    }

    private var previewBackground: AnyShapeStyle {
        switch theme {
        case .light:
            AnyShapeStyle(.white)
        case .dark:
            AnyShapeStyle(Color(red: 0.12, green: 0.13, blue: 0.16))
        case .system:
            AnyShapeStyle(
                LinearGradient(
                    colors: [.white, Color(red: 0.12, green: 0.13, blue: 0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private var previewText: Color {
        theme == .light ? Color.black.opacity(0.7) : .white.opacity(0.8)
    }

    private var previewCard: Color {
        theme == .light ? Color.black.opacity(0.08) : .white.opacity(0.12)
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
                    Label(
                        LocalizedStringKey(sortCriterion.localizationKey),
                        systemImage: sortDirection.systemImage
                    )
                        .font(.subheadline.weight(.medium))
                }
                .liquidGlassButton()
            }

            if filteredConnections.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey(connections.isEmpty ? "connections.empty" : "connections.noMatch"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(LocalizedStringKey(connections.isEmpty ? "connections.empty.description" : "connections.noMatch.description"))
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.connection.processName), \(byteRate(activity.totalSpeed)), \(activity.connection.routingDescription)")
        .accessibilityHint("accessibility.connectionDetails")
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

private func subscriptionSummary(_ subscriptionInfo: MihomoSubscriptionInfo) -> Text {
    var summary = Text("\(byteCount(subscriptionInfo.used)) / \(byteCount(subscriptionInfo.total))")
    if let usageFraction = subscriptionInfo.usageFraction {
        summary = summary + Text(" (\(Int((usageFraction * 100).rounded()))%")
        if let expirationDate = subscriptionInfo.expirationDate {
            summary = summary + Text(", ") + Text("resources.expires") + Text(expirationDate, format: .dateTime.year().month().day())
        }
        return summary + Text(")")
    }
    if let expirationDate = subscriptionInfo.expirationDate {
        return summary + Text(" (") + Text("resources.expires") + Text(expirationDate, format: .dateTime.year().month().day()) + Text(")")
    }
    return summary
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
                        LocalizedStringKey("profiles.empty"),
                        systemImage: "doc.badge.plus",
                        description: Text(LocalizedStringKey("profiles.empty.description"))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.snapshot.profiles)
            .navigationTitle(Text(LocalizedStringKey("navigation.profiles")))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingImporter = true } label: {
                        Label("profiles.import", systemImage: "square.and.arrow.down")
                    }
                    Button { showingRemoteSheet = true } label: {
                        Label("profiles.online", systemImage: "link.badge.plus")
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
    @Environment(\.locale) private var locale
    let profile: Profile
    @State private var showingRemoteEditor = false
    @State private var showingContentEditor = false
    @State private var showingProfileOverrideEditor = false
    @State private var showingDeleteConfirmation = false

    private var isActive: Bool {
        model.snapshot.activeProfileID == profile.id
    }

    private var deletionConfirmationTitle: Text {
        let localizedFormat = String(localized: "profiles.delete.confirmationTitle", locale: locale)
        return Text(verbatim: String(format: localizedFormat, locale: locale, arguments: [profile.name]))
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
                    if profile.source == .local || profile.remoteURL?.host == nil {
                        Text(LocalizedStringKey(profile.source.detailLocalizationKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(profile.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if isActive {
                    Text("profiles.active")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }

                Menu {
                    Button {
                        showingProfileOverrideEditor = true
                    } label: {
                        Label("profiles.overrides", systemImage: "curlybraces.square")
                    }

                    if profile.source == .remote {
                        Button {
                            showingRemoteEditor = true
                        } label: {
                            Label("profiles.edit", systemImage: "pencil")
                        }
                    }

                    Button {
                        showingContentEditor = true
                    } label: {
                        Label("profiles.editContent", systemImage: "doc.text")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("profiles.delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("accessibility.profileActions") + Text(verbatim: " \(profile.name)"))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(LocalizedStringKey(profile.source.localizationKey))
                        .textCase(.uppercase)
                    Text("profiles.updated") + Text(profile.updatedAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let subscriptionInfo = profile.subscriptionInfo {
                    HStack(spacing: 7) {
                        Label("common.subscription", systemImage: "chart.pie.fill")
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
                        Label("common.refresh", systemImage: "arrow.clockwise")
                    }
                    .liquidGlassButton()
                }

                Spacer()

                Button(LocalizedStringKey(isActive && model.isConnected ? "status.connected" : "common.connect")) {
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
        .sheet(isPresented: $showingContentEditor) {
            ProfileContentEditor(profile: profile)
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
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("common.delete", role: .destructive) {
                Task { await model.deleteProfile(profile) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("profiles.delete.description"))
        }
    }
}

private struct ProfileContentEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var contents = ""
    @State private var originalContents = ""
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView {
                        Text("common.loading") + Text(verbatim: " \(profile.name)")
                    }
                } else {
                    MultilineCodeEditor(
                        text: $contents,
                        language: .yaml,
                        minHeight: 360,
                        releasesResourcesOnDisappear: true
                    )
                }
            }
            .navigationTitle(Text(verbatim: profile.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task {
                            if await model.saveProfileContents(contents, for: profile) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isLoading || contents == originalContents)
                }
            }
            .task {
                guard let text = await model.profileContents(profile) else {
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
        .onDisappear {
            contents.removeAll(keepingCapacity: false)
            originalContents.removeAll(keepingCapacity: false)
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
                            Text("profiles.customOverride.title")
                                .font(.title3.weight(.semibold))
                            Text("profiles.customOverride.description")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $globalOverridesEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("profiles.customOverride.enableGlobal")
                            Text("profiles.customOverride.enableGlobal.description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    MultilineCodeEditor(
                        text: $contents,
                        language: .yaml,
                        minHeight: 320,
                        releasesResourcesOnDisappear: true
                    )

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("key!")
                                .foregroundStyle(.purple)
                            Text("overrides.replaceObject")
                        }
                        GridRow {
                            Text("+key / key+")
                                .foregroundStyle(.purple)
                            Text("overrides.arrayItems")
                        }
                        GridRow {
                            Text("<key>")
                                .foregroundStyle(.purple)
                            Text("overrides.escapeKey")
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
            .navigationTitle(Text(verbatim: profile.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        save(contents, globalOverridesEnabled)
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
#endif
        .onDisappear {
            contents.removeAll(keepingCapacity: false)
        }
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
                            Text(LocalizedStringKey(isEditing ? "profiles.editOnline" : "profiles.addOnline"))
                                .font(.title3.weight(.semibold))
                            Text(LocalizedStringKey(isEditing ? "profiles.editOnline.description" : "profiles.addOnline.description"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("profiles.subscriptionURL", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                        TextField(text: $address, prompt: Text(verbatim: SharedText.subscriptionURLPlaceholder)) {
                            Text(verbatim: SharedText.subscriptionURLPlaceholder)
                        }
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
                            Label("profiles.subscriptionURL.invalid", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("profiles.name", systemImage: "text.cursor")
                            .font(.subheadline.weight(.semibold))
                        TextField("profiles.name.placeholder", text: $name)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .liquidGlassCard()
                        Text("profiles.name.description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("profiles.userAgent", systemImage: "network")
                            .font(.subheadline.weight(.semibold))
                        TextField(
                            "profiles.userAgent",
                            text: $customUserAgent,
                            prompt: Text("profiles.userAgent.placeholder") + Text(verbatim: " \(MihomoCoreVersion.userAgent)")
                        )
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .customUserAgent)
                            .padding(14)
                            .liquidGlassCard()
                        Text(LocalizedStringKey(isEditing ? "profiles.userAgent.editDescription" : "profiles.userAgent.addDescription"))
                            + Text(verbatim: " \(MihomoCoreVersion.userAgent).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, pagePadding)
                .padding(.vertical, pagePadding)
            }
            .navigationTitle(Text(LocalizedStringKey(isEditing ? "profiles.editOnline" : "profiles.online")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(isEditing ? "profiles.saveChanges" : "profiles.add")) {
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
            .animation(reduceMotion ? nil : .smooth, value: model.delays)
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
                    Text(LocalizedStringKey(usesCompactLayout ? "proxies.noResult" : "proxies.noDelayResult"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.testDelay(for: node) }
                } label: {
                    Label("proxies.testDelay", systemImage: "timer")
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
        .accessibilityHint(LocalizedStringKey(isSelected ? "accessibility.currentlySelected" : "accessibility.selectNode"))
    }
}

private struct OverridesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
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
            Label("overrides.save", systemImage: "checkmark")
        }
        .liquidGlassButton(prominent: true)
        .disabled(draft == model.snapshot.overrides)
    }

    private func portField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
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

    private var sparxieInstallURL: URL {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&=+?#")
        let secret = draft.controllerSecret.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? draft.controllerSecret

        return URL(string: "sparxie://install-target?url=http%3A%2F%2F127.0.0.1%3A\(draft.controllerPort)&name=Swihomo&type=mihomo&secret=\(secret)")!
    }

    private var controllerPortField: some View {
        HStack(spacing: 8) {
            portField("overrides.controllerPort", value: $draft.controllerPort)
            Menu {
                Section("common.exportTo") {
                    Button {
                        openURL(sparxieInstallURL)
                    } label: {
                        Label {
                            Text(verbatim: SharedText.sparxie)
                        } icon: {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("accessibility.exportControllerConfiguration")
            .help("accessibility.exportControllerConfiguration")
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
                                Text("overrides.basicSettings")
                                    .font(.headline)
                                Text("overrides.basicSettings.description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            if usesCompactLayout {
                                Label("overrides.routingMode", systemImage: "arrow.triangle.branch")
                                Picker("overrides.routingMode", selection: $draft.mode) {
                                    ForEach(ProxyMode.allCases) { mode in
                                        Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            } else {
                                HStack {
                                    Label("overrides.routingMode", systemImage: "arrow.triangle.branch")
                                    Spacer()
                                    Picker("overrides.routingMode", selection: $draft.mode) {
                                        ForEach(ProxyMode.allCases) { mode in
                                            Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                }
                            }

                            HStack {
                                Label("overrides.mihomoLogLevel", systemImage: "text.line.first.and.arrowtriangle.forward")
                                Spacer()
                                Picker("overrides.mihomoLogLevel", selection: $draft.logLevel) {
                                    ForEach(MihomoLogLevel.allCases) { level in
                                        Text(LocalizedStringKey(level.localizationKey)).tag(level)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("overrides.allowLAN", isOn: $draft.allowLAN)
                            Toggle("overrides.enableIPv6", isOn: $draft.ipv6Enabled)
                            Toggle("overrides.enableDNS", isOn: $draft.dnsEnabled)
                        }

                        Divider()

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 28) {
                                portField("overrides.mixedPort", value: $draft.mixedPort)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                controllerPortField
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                portField("overrides.mixedPort", value: $draft.mixedPort)
                                controllerPortField
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.secondary)
                            if isControllerSecretVisible {
                                TextField("overrides.controllerSecret", text: $draft.controllerSecret)
                            } else {
                                SecureField("overrides.controllerSecret", text: $draft.controllerSecret)
                            }
                            Button {
                                isControllerSecretVisible.toggle()
                            } label: {
                                Image(systemName: isControllerSecretVisible ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(LocalizedStringKey(isControllerSecretVisible ? "accessibility.hideControllerSecret" : "accessibility.showControllerSecret"))
                            .help(LocalizedStringKey(isControllerSecretVisible ? "accessibility.hideControllerSecret" : "accessibility.showControllerSecret"))
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
                                Text("overrides.customYAML")
                                    .font(.headline)
                                Text("overrides.customYAML.description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Link(destination: URL(string: "https://clashparty.org/docs/guide/override/yaml")!) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("accessibility.openOverrideReference")
                        }

                        MultilineCodeEditor(
                            text: $draft.customYAML,
                            language: .yaml,
                            minHeight: 320
                        )

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("key!")
                                    .foregroundStyle(.purple)
                                Text("overrides.replaceObject")
                            }
                            GridRow {
                                Text("+key / key+")
                                    .foregroundStyle(.purple)
                                Text("overrides.arrayItems")
                            }
                            GridRow {
                                Text("<key>")
                                    .foregroundStyle(.purple)
                                Text("overrides.escapeKey")
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
                            Text(LocalizedStringKey(draft == model.snapshot.overrides ? "overrides.allSaved" : "overrides.unsavedChanges"))
                                .font(.subheadline.weight(.semibold))
                            HStack(alignment: .bottom, spacing: 12) {
                                Text("overrides.saveDescription")
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
                                Text(LocalizedStringKey(draft == model.snapshot.overrides ? "overrides.allSaved" : "overrides.unsavedChanges"))
                                    .font(.subheadline.weight(.semibold))
                                Text("overrides.saveDescription")
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
            .navigationTitle(Text(LocalizedStringKey("navigation.overrides")))
            .onAppear { draft = model.snapshot.overrides }
            .onChange(of: model.snapshot.overrides) { _, overrides in
                draft = overrides
            }
            .confirmationDialog(
                Text(LocalizedStringKey("overrides.reconnect.confirmationTitle")),
                isPresented: $showingReconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("common.reconnect") {
                    model.reconnect()
                }
                Button("common.notNow", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("overrides.reconnect.description"))
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
                    Text("resources.description")
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
                        LocalizedStringKey(model.isConnected ? "resources.empty" : "resources.connectToView"),
                        systemImage: "externaldrive.connected.to.line.below",
                        description: Text(LocalizedStringKey(model.isConnected ? "resources.empty.description" : "resources.connectToView.description"))
                    )
                }
            }
            .navigationTitle(Text(LocalizedStringKey("navigation.resources")))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.reloadExternalResources() }
                    } label: {
                        Label("common.refresh", systemImage: "arrow.clockwise")
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
                            Text(LocalizedStringKey(resource.kind.localizationKey))
                            Text(resource.providerType.uppercased())
                            if let behavior = resource.behavior, !behavior.isEmpty {
                                Text(behavior.uppercased())
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(LocalizedStringKey(resource.isPresent ? "resources.ready" : "resources.missing"))
                        .font(.caption2.bold())
                        .foregroundStyle(resource.isPresent ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if resource.kind == .geoData {
                        Label(
                            LocalizedStringKey(resource.isPresent ? "resources.cached" : "resources.notCached"),
                            systemImage: resource.isPresent ? "internaldrive.fill" : "exclamationmark.triangle"
                        )
                    }

                    HStack(spacing: 8) {
                        Label("resources.lastUpdated", systemImage: "clock")
                        Spacer()
                        if let updatedAt = resource.updatedAt {
                            Text(updatedAt, format: .dateTime.year().month().day().hour().minute())
                        } else {
                            Text("common.unavailable")
                        }
                    }

                    if resource.kind != .geoData, let subscriptionInfo {
                        HStack(spacing: 8) {
                            Label("common.subscription", systemImage: "chart.pie.fill")
                            Spacer()
                            subscriptionSummary(subscriptionInfo)
                                .lineLimit(1)
                        }
                    } else if resource.kind != .geoData, let ruleCount = resource.ruleCount {
                        HStack(spacing: 8) {
                            Label("resources.rules", systemImage: "list.number")
                            Spacer()
                            Text("\(ruleCount) ") + Text("resources.ruleCountSuffix")
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
                            Label("common.update", systemImage: "arrow.down.circle")
                                .foregroundStyle(.white)
                        }
                    }
                    .liquidGlassButton(prominent: true)
                    .disabled(!model.isConnected || isUpdating)

                    if resource.kind != .geoData {
                        Button("common.edit", action: edit)
                            .liquidGlassButton()
                            .disabled(!resource.isPresent || isUpdating)
                    }
                    Button("common.replace", action: replace)
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
                    ProgressView {
                        Text("common.loading") + Text(verbatim: " \(resource.name)")
                    }
                } else if !isText {
                    ContentUnavailableView(
                        LocalizedStringKey("resources.unsupportedEncoding"),
                        systemImage: "doc.questionmark",
                        description: Text(LocalizedStringKey("resources.unsupportedEncoding.description"))
                    )
                } else {
                    MultilineCodeEditor(
                        text: $contents,
                        language: .yaml,
                        minHeight: 360,
                        releasesResourcesOnDisappear: true
                    )
                }
            }
            .navigationTitle(Text(verbatim: resource.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
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
        .onDisappear {
            contents.removeAll(keepingCapacity: false)
            originalContents.removeAll(keepingCapacity: false)
        }
    }
}

private struct MultilineCodeEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding private var text: String
    private let language: LanguageConfiguration
    private let minHeight: CGFloat
    private let releasesResourcesOnDisappear: Bool
    @State private var position = CodeEditor.Position()
    @State private var messages = Set<TextLocated<Message>>()
    @State private var isEditorActive = true
    @State private var editorID = UUID()

    init(
        text: Binding<String>,
        language: LanguageConfiguration = .none,
        minHeight: CGFloat,
        releasesResourcesOnDisappear: Bool = false
    ) {
        _text = text
        self.language = language
        self.minHeight = minHeight
        self.releasesResourcesOnDisappear = releasesResourcesOnDisappear
    }

    var body: some View {
        Group {
            if isEditorActive {
                CodeEditor(
                    text: $text,
                    position: $position,
                    messages: $messages,
                    language: language
                )
                .id(editorID)
                .environment(
                    \.codeEditorTheme,
                    colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
                )
                .environment(
                    \.codeEditorLayoutConfiguration,
                    CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)
                )
            }
        }
        .frame(minHeight: minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .onAppear {
            isEditorActive = true
        }
        .onDisappear {
            guard releasesResourcesOnDisappear else { return }
            isEditorActive = false
            editorID = UUID()
            position = CodeEditor.Position()
            messages.removeAll(keepingCapacity: false)
        }
    }
}

private extension LanguageConfiguration {
    static let yaml = LanguageConfiguration(
        name: "YAML",
        supportsSquareBrackets: true,
        supportsCurlyBrackets: true,
        caseInsensitiveReservedIdentifiers: true,
        indentationSensitiveScoping: true,
        stringRegex: /"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'/,
        characterRegex: nil,
        numberRegex: /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/,
        singleLineComment: "#",
        nestedComment: nil,
        identifierRegex: /[A-Za-z_][A-Za-z0-9_-]*/,
        operatorRegex: nil,
        reservedIdentifiers: ["true", "false", "null", "yes", "no", "on", "off"],
        reservedOperators: []
    )
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
                    Picker("common.source", selection: $filter) {
                        ForEach(LogFilter.allCases) { filter in
                            Text(filter.titleKey).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("common.level", selection: $levelFilter) {
                        ForEach(LogLevelFilter.allCases) { level in
                            Text(level.titleKey).tag(level)
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
                        Button(role: .destructive) {
                            showingClearLogsConfirmation = true
                        } label: {
                            Label("logs.clearLogs", systemImage: "trash")
                        }
                    } label: {
                        Label("common.more", systemImage: "ellipsis.circle")
                    }

                    Button {
                        Task { await model.reloadLogs() }
                    } label: {
                        Label("common.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isConnected)
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

private extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
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
