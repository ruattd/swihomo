import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ExternalResourcesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingResource: ExternalResource?
    @State private var importedResource: ExternalResource?
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Text("resources.description")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }

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
            .uniformTopScrollEdge()
            .overlay {
                if model.externalResources.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(LocalizedStringKey(model.isConnected ? "resources.empty" : "resources.connectToView"))
                        } icon: {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .frame(height: 40)
                        }
                    } description: {
                        Text(LocalizedStringKey(model.isConnected ? "resources.empty.description" : "resources.connectToView.description"))
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey("navigation.resources")))
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

    private var isUpdating: Bool { model.updatingExternalResourceIDs.contains(resource.id) }
    private var tint: Color {
        switch resource.kind {
        case .proxyProvider: .orange
        case .ruleProvider: .purple
        case .geoData: .teal
        }
    }
    private var icon: String {
        switch resource.kind {
        case .proxyProvider: "point.3.connected.trianglepath.dotted"
        case .ruleProvider: "list.bullet.rectangle"
        case .geoData: "globe.americas.fill"
        }
    }
    private var subscriptionInfo: MihomoSubscriptionInfo? { resource.kind == .proxyProvider ? resource.subscriptionInfo : nil }

    // Custom surface (not GroupBox) so the usage fill can span edge-to-edge behind the content;
    // visually identical to GroupBox: quaternarySystemFill + boxCornerRadius.
    var body: some View {
        cardContent
            .padding(8)
            .background(alignment: .topLeading) {
                if let usageFraction = subscriptionInfo?.usageFraction {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(tint.opacity(0.13))
                            .frame(width: geometry.size.width * CGFloat(usageFraction))
                            .allowsHitTesting(false)
                    }
                    .mask(RoundedRectangle(cornerRadius: SurfaceMetrics.boxCornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .contentCard()
    }

    private var cardContent: some View {
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
