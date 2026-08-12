import Foundation
import SwiftUI

struct PreferencesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appTheme") private var selectedTheme = AppTheme.system.rawValue
    @State private var systemThemeResetID = UUID()
    @AppStorage("automaticallyReclaimsMemory") private var automaticallyReclaimsMemory = false
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

            Text("preferences.packetTunnel.reconnectDescription")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(verbatim: SharedText.mtu)
                Spacer()
                TextField(SharedText.mtu, text: packetTunnelMTUInputBinding)
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

            Text("preferences.packetTunnel.mtu.description")
                .font(.caption)
                .foregroundStyle(packetTunnelMTUInputIsInvalid ? .red : .secondary)

            Toggle("preferences.packetTunnel.routeIPv6", isOn: $packetTunnelIPv6Enabled)

            Text("preferences.packetTunnel.routeIPv6.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            packetTunnelEditorSection(
                titleKey: "preferences.packetTunnel.customDNS",
                descriptionKey: "preferences.packetTunnel.customDNS.description",
                text: $packetTunnelCustomDNSServers,
                minHeight: 100,
                field: .customDNS
            )

            Divider()

            Toggle("preferences.packetTunnel.includeAllNetworks", isOn: $packetTunnelIncludeAllNetworks)

            Text("preferences.packetTunnel.includeAllNetworks.description")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("preferences.packetTunnel.excludeCellularServices", isOn: $packetTunnelExcludeCellularServices)
                .disabled(!packetTunnelIncludeAllNetworks)

            Text("preferences.packetTunnel.excludeCellularServices.description")
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(!packetTunnelIncludeAllNetworks)

            Toggle("preferences.packetTunnel.bypassLocalNetworks", isOn: $packetTunnelBypassesPrivateNetworks)
                .disabled(!packetTunnelIncludeAllNetworks)

            Text("preferences.packetTunnel.bypassLocalNetworks.description")
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(!packetTunnelIncludeAllNetworks)

            Toggle("preferences.packetTunnel.bypassAPNs", isOn: $packetTunnelBypassAPNs)
                .disabled(!packetTunnelIncludeAllNetworks)

            Text("preferences.packetTunnel.bypassAPNs.description")
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(!packetTunnelIncludeAllNetworks)

            Divider()

            packetTunnelEditorSection(
                titleKey: "preferences.packetTunnel.bypassIPRanges",
                descriptionKey: "preferences.packetTunnel.bypassIPRanges.description",
                text: $packetTunnelBypassCIDRs,
                minHeight: 120,
                field: .bypassIPRanges
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 20)
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
        Text(titleKey)
            .font(.subheadline.weight(.medium))

        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 10) {
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

                Text(descriptionKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            MultilineCodeEditor(text: text, minHeight: minHeight)

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
            .liquidGlassCard(cornerRadius: 20)
            .padding(20)
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
