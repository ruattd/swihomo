import Foundation
import SwiftUI

struct PreferencesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appTheme") private var selectedTheme = AppTheme.system.rawValue
    @State private var systemThemeResetID = UUID()
    @AppStorage("automaticallyReclaimsMemory") private var automaticallyReclaimsMemory = false
    @AppStorage("replaceGeoDatabasesWithRulesets") private var replaceGeoDatabasesWithRulesets = false
    @AppStorage("realtimeDelayTest") private var realtimeDelayTest = false
    @AppStorage("delayTestMaxConcurrency") private var delayTestMaxConcurrency = 4
    @AppStorage("autoCollapseProxyGroups") private var autoCollapseProxyGroups = false
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    @AppStorage("menuBarDisplay") private var menuBarDisplay = "iconAndSpeed"
    @AppStorage("appLogLevel") private var appLogLevel = LogLevel.info.rawValue
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage("packetTunnelBypassesPrivateNetworks") private var packetTunnelBypassesPrivateNetworks = false
    @AppStorage("packetTunnelBypassAPNs") private var packetTunnelBypassAPNs = false
    @AppStorage("packetTunnelExcludeCellularServices") private var packetTunnelExcludeCellularServices = true
    @AppStorage("packetTunnelIncludeAllNetworks") private var packetTunnelIncludeAllNetworks = false
    @AppStorage("packetTunnelBypassCIDRs") private var packetTunnelBypassCIDRs = ""
    @AppStorage("packetTunnelMTU") private var packetTunnelMTU = PacketTunnelMTULimits.defaultValue
    @AppStorage("packetTunnelCustomDNSServers") private var packetTunnelCustomDNSServers = ""
    @AppStorage("packetTunnelIPv6Enabled") private var packetTunnelIPv6Enabled = true
    @State private var editingPacketTunnelField: PacketTunnelTextField?
    @State private var packetTunnelMTUInput: String?
    #if os(macOS)
    @AppStorage("hidesDockIcon") private var hidesDockIcon = false
    #endif

    var body: some View {
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
        .navigationTitle(Text(LocalizedStringKey("navigation.preferences")))
    }

    private var appearanceSettings: some View {
        Section {
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
            // Default-style pickers with a visible label: iOS renders a full-width navigation
            // row (push to select, press-and-hold quick select); macOS renders the title with
            // a popup menu — the native settings row on both platforms.
            VStack(alignment: .leading, spacing: 6) {
                Picker("preferences.application.logLevel", selection: $appLogLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(LocalizedStringKey(level.localizationKey)).tag(level.rawValue)
                    }
                }
                Text("preferences.application.logLevel.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("preferences.application.language", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    languageLabel(for: language).tag(language.rawValue)
                }
            }

            PreferenceRow(
                title: Text("preferences.application.autoCollapseProxyGroups"),
                description: Text("preferences.application.autoCollapseProxyGroups.description")
            ) {
                Toggle("preferences.application.autoCollapseProxyGroups", isOn: $autoCollapseProxyGroups)
                    .labelsHidden()
            }
        } header: {
            SectionHeaderLabel("preferences.application.title", systemImage: "app.badge")
        }
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
                        editingPacketTunnelField = field
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
        Section {
            Toggle("preferences.menuBar.show", isOn: $showsMenuBar)

            PreferenceRow(
                title: Text("preferences.menuBar.display"),
                description: menuBarDisplay == MenuBarDisplay.icon.rawValue
                    ? Text("preferences.menuBar.display.iconOnlyDescription")
                    : nil
            ) {
                Picker("preferences.menuBar.display", selection: $menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { display in
                        Text(display.titleKey).tag(display.rawValue)
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

private enum PacketTunnelTextField: String, Identifiable {
    case customDNS
    case bypassIPRanges

    var id: String { rawValue }
}

private struct PacketTunnelTextEditor: View {
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
