import Foundation
#if os(macOS)
import AppKit
#endif
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppSetting(\.appTheme) private var selectedTheme
    @State private var systemThemeResetID = UUID()
    @AppSetting(\.automaticallyReclaimsMemory) private var automaticallyReclaimsMemory
    @AppSetting(\.replaceGeoDatabasesWithRulesets) private var replaceGeoDatabasesWithRulesets
    @AppSetting(\.realtimeDelayTest) private var realtimeDelayTest
    @AppSetting(\.delayTestMaxConcurrency) private var delayTestMaxConcurrency
    @AppSetting(\.autoCollapseProxyGroups) private var autoCollapseProxyGroups
    @AppSetting(\.subscriptionInfoDisplay) private var subscriptionInfoDisplay
    @AppSetting(\.showsMenuBar) private var showsMenuBar
    @AppSetting(\.menuBarDisplay) private var menuBarDisplay
    @AppSetting(\.appLogLevel) private var appLogLevel
    @AppSetting(\.appLanguage) private var selectedLanguage
    @AppSetting(\.packetTunnelBypassesPrivateNetworks) private var packetTunnelBypassesPrivateNetworks
    @AppSetting(\.packetTunnelBypassAPNs) private var packetTunnelBypassAPNs
    @AppSetting(\.packetTunnelExcludeCellularServices) private var packetTunnelExcludeCellularServices
    @AppSetting(\.packetTunnelIncludeAllNetworks) private var packetTunnelIncludeAllNetworks
    @AppSetting(\.packetTunnelBypassCIDRs) private var packetTunnelBypassCIDRs
    @AppSetting(\.packetTunnelMTU) private var packetTunnelMTU
    @AppSetting(\.packetTunnelCustomDNSServers) private var packetTunnelCustomDNSServers
    @AppSetting(\.packetTunnelIPv6Enabled) private var packetTunnelIPv6Enabled
    @AppSetting(\.packetTunnelUseMipstack) private var packetTunnelUseMipstack
    @State private var packetTunnelMTUInput: String?
#if os(iOS)
    @State private var editorPath: [CompactRoute] = []
    @Environment(\.pushCompactRoute) private var pushCompactRoute
#endif
#if os(macOS)
    @State private var editingPacketTunnelField: PacketTunnelTextField?
    @AppSetting(\.hidesDockIcon) private var hidesDockIcon
#endif

    var body: some View {
#if os(iOS)
        EditorPageHost(path: $editorPath) {
            Form {
                appearanceSettings
                applicationSettings
                packetTunnelSettings
                memoryManagementSettings
            }
            .formStyle(.grouped)
            .uniformTopScrollEdge()
            .detailPageTitle("navigation.preferences")
        } destination: { route in
            Self.editorDestination(
                route,
                model: model,
                push: { editorPath.append($0) },
                pop: { editorPath.removeLast() }
            )
        }
#else
        Form {
            appearanceSettings
#if os(macOS)
            menuBarSettings
#endif
            applicationSettings
            packetTunnelSettings
            memoryManagementSettings
        }
        .formStyle(.grouped)
        .uniformTopScrollEdge()
        .detailPageTitle("navigation.preferences")
#endif
    }
    @MainActor @ViewBuilder
    static func editorDestination(
        _ route: CompactRoute,
        model: AppModel,
        push: @escaping (CompactRoute) -> Void,
        pop: @escaping () -> Void
    ) -> some View {
        @AppSetting(\.packetTunnelCustomDNSServers) var packetTunnelCustomDNSServers
        @AppSetting(\.packetTunnelBypassCIDRs) var packetTunnelBypassCIDRs

        switch route {
        case .packetTunnelEditor(let field):
            switch field {
            case .customDNS:
                PacketTunnelTextEditor(
                    titleKey: "preferences.packetTunnel.customDNS",
                    descriptionKey: "preferences.packetTunnel.customDNS.description",
                    text: $packetTunnelCustomDNSServers,
                    minHeight: 220
                )
            case .bypassIPRanges:
                PacketTunnelTextEditor(
                    titleKey: "preferences.packetTunnel.bypassIPRanges",
                    descriptionKey: "preferences.packetTunnel.bypassIPRanges.description",
                    text: $packetTunnelBypassCIDRs,
                    minHeight: 240
                )
            }
        default:
            EmptyView()
        }
    }
#if os(iOS)
    private func openEditor(_ route: CompactRoute) {
        if let pushCompactRoute {
            pushCompactRoute(route)
        } else {
            editorPath.append(route)
        }
    }
#endif

    private var appearanceSettings: some View {
        Section {
            if horizontalSizeClass == .compact {
                Picker("preferences.appearance.title", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.titleKey).tag(theme)
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
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeaderLabel("preferences.appearance.title", systemImage: "paintpalette")
                Text("preferences.appearance.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var memoryManagementSettings: some View {
        Section {
            PreferenceRow(
                title: Text("preferences.experimental.autoReclaimMemory"),
                description: Text("preferences.experimental.autoReclaimMemory.description")
            ) {
                Toggle("preferences.experimental.autoReclaimMemory", isOn: $automaticallyReclaimsMemory)
                    .labelsHidden()
            }

            PreferenceRow(
                title: Text("preferences.experimental.replaceGeoDatabases"),
                description: Text("preferences.experimental.replaceGeoDatabases.description")
            ) {
                Toggle("preferences.experimental.replaceGeoDatabases", isOn: $replaceGeoDatabasesWithRulesets)
                    .labelsHidden()
            }

            PreferenceRow(
                title: Text("preferences.experimental.useMipstack"),
                description: Text("preferences.experimental.useMipstack.description")
            ) {
                Toggle("preferences.experimental.useMipstack", isOn: $packetTunnelUseMipstack)
                    .labelsHidden()
            }

            PreferenceRow(
                title: Text("preferences.experimental.realtimeDelayTest"),
                description: Text("preferences.experimental.realtimeDelayTest.description")
            ) {
                Toggle("preferences.experimental.realtimeDelayTest", isOn: $realtimeDelayTest)
                    .labelsHidden()
            }

            PreferenceRow(
                title: Text("preferences.experimental.delayTestConcurrency"),
                description: Text("preferences.experimental.delayTestConcurrency.description")
            ) {
                HStack(spacing: 6) {
                    TextField("preferences.experimental.delayTestConcurrency", value: $delayTestMaxConcurrency, format: .number.grouping(.never))
                        .labelsHidden()
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                        .onChange(of: delayTestMaxConcurrency) { _, value in
                            delayTestMaxConcurrency = min(max(value, 1), 32)
                        }
                    Stepper("preferences.experimental.delayTestConcurrency", value: $delayTestMaxConcurrency, in: 1...32)
                        .labelsHidden()
                }
            }
            .disabled(!realtimeDelayTest)
        } header: {
            SectionHeaderLabel("preferences.experimental", systemImage: "flask")
        }
    }

    private var applicationSettings: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                SettingsPickerRow(
                    "preferences.application.logLevel",
                    selection: $appLogLevel,
                    options: LogLevel.allCases.map { ($0, Text(LocalizedStringKey($0.localizationKey))) }
                )
                Text("preferences.application.logLevel.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsPickerRow(
                "preferences.application.language",
                selection: $selectedLanguage,
                options: AppLanguage.allCases.map { language in
                    if let titleKey = language.titleKey {
                        (language, Text(titleKey))
                    } else {
                        (language, Text(verbatim: language.endonym ?? language.rawValue))
                    }
                }
            )

            PreferenceRow(
                title: Text("preferences.application.autoCollapseProxyGroups"),
                description: Text("preferences.application.autoCollapseProxyGroups.description")
            ) {
                Toggle("preferences.application.autoCollapseProxyGroups", isOn: $autoCollapseProxyGroups)
                    .labelsHidden()
            }

            SettingsPickerRow(
                "preferences.application.showSubscriptionInfo",
                selection: $subscriptionInfoDisplay,
                options: SubscriptionInfoDisplay.allCases.map { ($0, Text(LocalizedStringKey($0.localizationKey))) }
            )
        } header: {
            SectionHeaderLabel("preferences.application.title", systemImage: "app.badge")
        }
    }

    private var packetTunnelSettings: some View {
        Section {
            PreferenceRow(
                title: Text(verbatim: SharedText.mtu),
                description: Text("preferences.packetTunnel.mtu.description"),
                descriptionColor: packetTunnelMTUInputIsInvalid ? .red : .secondary
            ) {
                TextField(SharedText.mtu, text: packetTunnelMTUInputBinding)
                    .labelsHidden()
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .overlay {
                        if packetTunnelMTUInputIsInvalid {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.red, lineWidth: 1)
                        }
                    }
                    .onChange(of: packetTunnelMTUInput) { _, _ in
                        validatePacketTunnelMTUInput()
                    }
            }

            PreferenceRow(
                title: Text("preferences.packetTunnel.routeIPv6"),
                description: Text("preferences.packetTunnel.routeIPv6.description")
            ) {
                Toggle("preferences.packetTunnel.routeIPv6", isOn: $packetTunnelIPv6Enabled)
                    .labelsHidden()
            }

            packetTunnelEditorSection(
                titleKey: "preferences.packetTunnel.customDNS",
                descriptionKey: "preferences.packetTunnel.customDNS.description",
                text: $packetTunnelCustomDNSServers,
                minHeight: 100,
                field: .customDNS
            )

            PreferenceRow(
                title: Text("preferences.packetTunnel.includeAllNetworks"),
                description: Text("preferences.packetTunnel.includeAllNetworks.description")
            ) {
                Toggle("preferences.packetTunnel.includeAllNetworks", isOn: $packetTunnelIncludeAllNetworks)
                    .labelsHidden()
            }

            PreferenceRow(
                title: Text("preferences.packetTunnel.excludeCellularServices"),
                description: Text("preferences.packetTunnel.excludeCellularServices.description")
            ) {
                Toggle("preferences.packetTunnel.excludeCellularServices", isOn: $packetTunnelExcludeCellularServices)
                    .labelsHidden()
            }
            .disabled(!packetTunnelIncludeAllNetworks)

            PreferenceRow(
                title: Text("preferences.packetTunnel.bypassLocalNetworks"),
                description: Text("preferences.packetTunnel.bypassLocalNetworks.description")
            ) {
                Toggle("preferences.packetTunnel.bypassLocalNetworks", isOn: $packetTunnelBypassesPrivateNetworks)
                    .labelsHidden()
            }
            .disabled(!packetTunnelIncludeAllNetworks)

            PreferenceRow(
                title: Text("preferences.packetTunnel.bypassAPNs"),
                description: Text("preferences.packetTunnel.bypassAPNs.description")
            ) {
                Toggle("preferences.packetTunnel.bypassAPNs", isOn: $packetTunnelBypassAPNs)
                    .labelsHidden()
            }
            .disabled(!packetTunnelIncludeAllNetworks)

            packetTunnelEditorSection(
                titleKey: "preferences.packetTunnel.bypassIPRanges",
                descriptionKey: "preferences.packetTunnel.bypassIPRanges.description",
                text: $packetTunnelBypassCIDRs,
                minHeight: 120,
                field: .bypassIPRanges
            )
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeaderLabel("preferences.packetTunnel.title", systemImage: "point.3.connected.trianglepath.dotted")
                Text("preferences.packetTunnel.reconnectDescription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
#if os(macOS)
        .sheet(item: $editingPacketTunnelField) { field in
            NavigationStack {
                switch field {
                case .customDNS:
                    PacketTunnelTextEditor(
                        titleKey: "preferences.packetTunnel.customDNS",
                        descriptionKey: "preferences.packetTunnel.customDNS.description",
                        text: $packetTunnelCustomDNSServers,
                        minHeight: 220
                    )
                case .bypassIPRanges:
                    PacketTunnelTextEditor(
                        titleKey: "preferences.packetTunnel.bypassIPRanges",
                        descriptionKey: "preferences.packetTunnel.bypassIPRanges.description",
                        text: $packetTunnelBypassCIDRs,
                        minHeight: 240
                    )
                }
            }
        }
#endif
    }

    private var packetTunnelMTUInputBinding: Binding<String> {
        Binding(
            get: { packetTunnelMTUInput ?? String(packetTunnelMTU) },
            set: { packetTunnelMTUInput = $0 }
        )
    }

    private var packetTunnelMTUInputIsInvalid: Bool {
        guard let input = packetTunnelMTUInput else { return false }
        guard let mtu = Int(input) else { return true }
        return !((PacketTunnelMTULimits.minimum...PacketTunnelMTULimits.maximum).contains(mtu))
    }

    private func validatePacketTunnelMTUInput() {
        guard let input = packetTunnelMTUInput,
              let mtu = Int(input),
              (PacketTunnelMTULimits.minimum...PacketTunnelMTULimits.maximum).contains(mtu) else {
            return
        }

        packetTunnelMTU = mtu
        packetTunnelMTUInput = nil
    }

    @ViewBuilder
    private func packetTunnelEditorSection(
        titleKey: LocalizedStringKey,
        descriptionKey: LocalizedStringKey,
        text: Binding<String>,
        minHeight: CGFloat,
        field: PacketTunnelTextField
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleKey)
                .font(.subheadline.weight(.medium))

            if horizontalSizeClass == .compact {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    packetTunnelSummary(for: text.wrappedValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Button {
#if os(iOS)
                        openEditor(.packetTunnelEditor(field))
#else
                        editingPacketTunnelField = field
#endif
                    } label: {
                        Label("preferences.packetTunnel.edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                MultilineCodeEditor(text: text, minHeight: minHeight)
            }

            Text(descriptionKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func packetTunnelSummary(for text: String) -> Text {
        let nonEmptyLines = text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !nonEmptyLines.isEmpty else {
            return Text("preferences.packetTunnel.summary.empty")
        }

        let preview = nonEmptyLines
            .prefix(3)
            .map(String.init)
            .joined(separator: ", ")
        let suffix = nonEmptyLines.count > 3 ? ", …" : ""
        return Text(verbatim: preview + suffix)
    }

    @ViewBuilder
    private var themeOptions: some View {
        ForEach(AppTheme.allCases) { theme in
            ThemeOptionCard(
                theme: theme,
                isSelected: selectedTheme == theme
            ) {
                selectTheme(theme)
            }
        }
    }


    private func selectTheme(_ theme: AppTheme) {
        #if os(macOS)
        let resetID = UUID()
        systemThemeResetID = resetID

        guard theme == .system, selectedTheme != .system else {
            selectedTheme = theme
            return
        }

        let systemTheme = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? AppTheme.dark
            : AppTheme.light
        selectedTheme = systemTheme
        DispatchQueue.main.async {
            guard systemThemeResetID == resetID else { return }
            selectedTheme = .system
        }
        #else
        selectedTheme = theme
        #endif
    }

#if os(macOS)
    private var menuBarSettings: some View {
        Section {
            Toggle("preferences.menuBar.show", isOn: $showsMenuBar)

            PreferenceRow(
                title: Text("preferences.menuBar.display"),
                description: menuBarDisplay == .icon
                    ? Text("preferences.menuBar.display.iconOnlyDescription")
                    : nil
            ) {
                Picker("preferences.menuBar.display", selection: $menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { display in
                        Text(display.titleKey).tag(display)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .disabled(!showsMenuBar)

            PreferenceRow(
                title: Text("preferences.menuBar.hideDockIcon"),
                description: showsMenuBar ? nil : Text("preferences.menuBar.hideDockIcon.description")
            ) {
                Toggle("preferences.menuBar.hideDockIcon", isOn: $hidesDockIcon)
                    .labelsHidden()
            }
            .disabled(!showsMenuBar)
        } header: {
            SectionHeaderLabel("preferences.menuBar.title", systemImage: "menubar.rectangle")
        }
    }
#endif
}

enum PacketTunnelTextField: String, Identifiable {
    case customDNS
    case bypassIPRanges

    var id: String { rawValue }
}

struct PacketTunnelTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    let titleKey: LocalizedStringKey
    let descriptionKey: LocalizedStringKey
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(descriptionKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MultilineCodeEditor(text: $text, minHeight: minHeight)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(titleKey))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done") {
                    dismiss()
                }
            }
        }
    }
}
