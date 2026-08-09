import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
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
    @State private var isRefreshing = false

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
                        guard !isRefreshing else { return }
                        isRefreshing = true
                        Task {
                            defer { isRefreshing = false }
                            await model.refreshProfile(profile)
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("common.refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .liquidGlassButton()
                    .disabled(isRefreshing)
                    .accessibilityLabel(Text(LocalizedStringKey(isRefreshing ? "common.loading" : "common.refresh")))
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
                        (Text(LocalizedStringKey(isEditing ? "profiles.userAgent.editDescription" : "profiles.userAgent.addDescription"))
                            + Text(verbatim: " \(MihomoCoreVersion.userAgent)."))
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
