import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OverridesView: View {
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
                    GroupBox {
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
                    .padding(10)
                    }

                    GroupBox {
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

                        GroupBox {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                        }
                    }
                    .padding(10)
                    }

                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, usesCompactLayout ? 120 : 88)
            }
            .overlay(alignment: .bottom) {
                GroupBox {
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
                .padding(8)
                }
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
