import SwiftUI

/// A utility entry on the Tools page. Placeholder set until real tools land.
struct Tool: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let icon: String

    static let placeholderTools: [Tool] = [
        Tool(id: "speedTest", titleKey: "tools.speedTest", icon: "speedometer"),
        Tool(id: "ping", titleKey: "tools.ping", icon: "dot.radiowaves.right"),
        Tool(id: "dnsLookup", titleKey: "tools.dnsLookup", icon: "magnifyingglass"),
    ]
}

// iOS pushes this onto the enclosing stack (sidebar column / compact-tab outer
// stack), where plain NavigationLinks handle everything. macOS has no usable
// sidebar push — a NavigationStack inside the split view's sidebar column
// renders broken inline chrome (back chevron under the titlebar, the title
// squeezed in between) — so there ContentView swaps the column's content
// through LayerSwapHost (GPU-side layer animation), and this view renders its
// own header.
struct ToolsView: View {
    /// macOS only: closes the drill-in and restores the home grid. Nil when the
    /// view is rendered as a detail-column page (FeatureDetailView needs the
    /// case for switch exhaustiveness, but macOS never selects .tools there).
    let onClose: (() -> Void)?

    #if os(macOS)
    @State private var selectedTool: Tool?
    #endif

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        #if os(macOS)
        // Sub-page swap runs in the same layer host as the outer drill-in:
        // GPU-side animation, no re-rasterization of the glass rows.
        LayerSwapHost(selection: selectedTool?.id, direction: selectedTool != nil ? .push : .pop) { toolID in
            if let toolID, let tool = Tool.placeholderTools.first(where: { $0.id == toolID }) {
                ToolPlaceholderView(tool: tool, onBack: { selectedTool = nil })
            } else {
                toolsList
            }
        }
        #else
        Form {
            Section {
                ForEach(Tool.placeholderTools) { tool in
                    NavigationLink {
                        ToolPlaceholderView(tool: tool)
                    } label: {
                        Label(tool.titleKey, systemImage: tool.icon)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .uniformTopScrollEdge()
        .detailPageTitle("navigation.tools")
        #endif
    }

    #if os(macOS)
    private var toolsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolsPageHeader(titleKey: "navigation.tools", onBack: onClose)

                ForEach(Tool.placeholderTools) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        ToolRow(tool: tool)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            // macOS scroll indicators overlay the rows; reserve their lane.
            .padding(.trailing, 4)
        }
        .uniformTopScrollEdge()
    }
    #endif
}

#if os(macOS)
/// In-content page header for sidebar drill-ins: glass back button + title,
/// matching HomeView's in-content header slot.
private struct ToolsPageHeader: View {
    let titleKey: LocalizedStringKey
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        // .glass hugs the label; an explicit 24pt label + glass
                        // padding lands at ~32pt, matching system toolbar buttons.
                        .frame(width: 24, height: 24)
                }
                .liquidGlassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("common.back"))
            }
            Text(titleKey)
                .font(.title.bold())
        }
        .padding(.bottom, 2)
    }
}

// Sized and padded like HomeBannerRow so the tools list aligns with the grid.
private struct ToolRow: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.title3.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            Text(tool.titleKey)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous))
        .liquidGlassCard(interactive: true)
    }
}
#endif

private struct ToolPlaceholderView: View {
    let tool: Tool
    /// macOS only: pops back to the tools list. Nil = rendered inside a
    /// navigation stack (iOS), where the system back button handles it.
    var onBack: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            ToolsPageHeader(titleKey: tool.titleKey, onBack: onBack)
            ContentUnavailableView {
                Label(tool.titleKey, systemImage: tool.icon)
            } description: {
                Text("tools.placeholder")
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .padding(.trailing, 4)
        #else
        ContentUnavailableView {
            Label(tool.titleKey, systemImage: tool.icon)
        } description: {
            Text("tools.placeholder")
        }
        .navigationTitle(tool.titleKey)
        #endif
    }
}
