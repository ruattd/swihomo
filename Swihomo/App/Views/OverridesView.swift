import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OverridesView: View {
    @EnvironmentObject private var model: AppModel
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
        // Inside the floating glass bar: glass-on-glass buttons get demoted, so use a solid prominent style.
        .buttonStyle(.borderedProminent)
        .disabled(draft == model.snapshot.overrides)
    }

    private func portField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            TextField(title, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .onChange(of: value.wrappedValue) { _, port in
                    value.wrappedValue = min(max(port, 1), 65535)
                }
            Stepper(title, value: value, in: 1...65535)
                .labelsHidden()
        }
    }

    private func controllerSecretField(maxWidth: CGFloat?) -> some View {
        HStack(spacing: 6) {
            Group {
                if isControllerSecretVisible {
                    TextField("overrides.controllerSecret", text: $draft.controllerSecret)
                } else {
                    SecureField("overrides.controllerSecret", text: $draft.controllerSecret)
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: maxWidth, alignment: .trailing)

            Button { isControllerSecretVisible.toggle() } label: {
                Image(systemName: isControllerSecretVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(isControllerSecretVisible ? "accessibility.hideControllerSecret" : "accessibility.showControllerSecret")))
            .help(Text(LocalizedStringKey(isControllerSecretVisible ? "accessibility.hideControllerSecret" : "accessibility.showControllerSecret")))
            .frame(width: 20)
            .contentShape(Rectangle())
            .padding(4)
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
            portField("overrides.controllerPort", value: $draft.controllerPort)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                yamlSection
            }
            .formStyle(.grouped)
            .uniformTopScrollEdge()
            .contentMargins(.bottom, 88, for: .scrollContent)
            .overlay(alignment: .bottom) {
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

    private var basicSection: some View {
        Section {
            Picker("overrides.routingMode", selection: $draft.mode) {
                ForEach(ProxyMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
                }
            }
            Picker("overrides.mihomoLogLevel", selection: $draft.logLevel) {
                ForEach(MihomoLogLevel.allCases) { level in
                    Text(LocalizedStringKey(level.localizationKey)).tag(level)
                }
            }
            Toggle("overrides.allowLAN", isOn: $draft.allowLAN)
            Toggle("overrides.enableIPv6", isOn: $draft.ipv6Enabled)
            Toggle("overrides.enableDNS", isOn: $draft.dnsEnabled)
            PreferenceRow(title: Text("overrides.mixedPort")) {
                portField("overrides.mixedPort", value: $draft.mixedPort)
            }
            PreferenceRow(title: Text("overrides.controllerPort")) {
                controllerPortField
            }
            ViewThatFits(in: .horizontal) {
                PreferenceRow(title: Text("overrides.controllerSecret")) {
                    controllerSecretField(maxWidth: 200)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("overrides.controllerSecret")
                    controllerSecretField(maxWidth: nil)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                Label("overrides.basicSettings", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                Text("overrides.basicSettings.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var yamlSection: some View {
        Section {
            MultilineCodeEditor(
                text: $draft.customYAML,
                language: .yaml,
                minHeight: 320
            )
            .listRowInsets(.settingsRow)

            Link(destination: URL(string: "https://clashparty.org/docs/guide/override/yaml")!) {
                Label("accessibility.openOverrideReference", systemImage: "arrow.up.right.square")
            }
            .help("accessibility.openOverrideReference")
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                Label("overrides.customYAML", systemImage: "curlybraces.square")
                    .font(.title3.weight(.semibold))
                Text("overrides.customYAML.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("key!").foregroundStyle(.purple)
                        Text("overrides.replaceObject")
                    }
                    GridRow {
                        Text("+key / key+").foregroundStyle(.purple)
                        Text("overrides.arrayItems")
                    }
                    GridRow {
                        Text("<key>").foregroundStyle(.purple)
                        Text("overrides.escapeKey")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

}
