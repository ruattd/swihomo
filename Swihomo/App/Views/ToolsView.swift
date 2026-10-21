import SwiftUI

/// A utility entry on the Tools page. Placeholder set until real tools land.
struct Tool: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let icon: String

    static let placeholderTools: [Tool] = [
        Tool(id: "icloudSync", titleKey: "tools.iCloudSync", icon: "icloud"),
        Tool(id: "speedTest", titleKey: "tools.speedTest", icon: "speedometer"),
        Tool(id: "ping", titleKey: "tools.ping", icon: "dot.radiowaves.right"),
        Tool(id: "dnsLookup", titleKey: "tools.dnsLookup", icon: "magnifyingglass"),
    ]

    /// Detail page for a tool id, shared by the macOS detail-column page host
    /// and the iOS typed-stack destinations.
    @ViewBuilder
    static func detailView(id: String) -> some View {
        if id == "icloudSync" {
            ICloudSyncSettingsView()
        } else if let tool = placeholderTools.first(where: { $0.id == id }) {
            ToolPlaceholderView(tool: tool)
        }
    }
}

// Wide layouts (macOS, iPad) never push tool pages inside the sidebar
// column — macOS has no usable sidebar push (a NavigationStack there renders
// broken inline chrome), and on both the tool page belongs in the detail
// column. Tool taps therefore hand the selection to the container through
// onSelectTool: ContentView swaps the macOS detail page / iPad detail
// column, while the compact iPhone layout pushes onto its outer typed stack
// (the system owns the push animation, back button, and pop state).
struct ToolsView: View {
    /// macOS only: closes the drill-in and restores the home grid. Nil when the
    /// view is rendered as a detail-column page (FeatureDetailView needs the
    /// case for switch exhaustiveness, but macOS never selects .tools there).
    let onClose: (() -> Void)?

    /// Tool tap handler. Wide layouts drive their detail column with it; the
    /// compact iPhone layout pushes onto the enclosing typed stack. Threaded
    /// explicitly — custom environment values do not reliably reach
    /// navigationDestination content (probed: row taps no-op'd).
    let onSelectTool: ((Tool) -> Void)?

    init(onClose: (() -> Void)? = nil, onSelectTool: ((Tool) -> Void)? = nil) {
        self.onClose = onClose
        self.onSelectTool = onSelectTool
    }

    var body: some View {
        #if os(macOS)
        toolsList
        #else
        // Card rows match the first-level grid. Taps push onto the enclosing
        // typed stack via the explicitly threaded pusher — plain links inside
        // a path-based stack desync pop state.
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Tool.placeholderTools) { tool in
                    Button {
                        onSelectTool?(tool)
                    } label: {
                        ToolRow(tool: tool)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
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
                        onSelectTool?(tool)
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
/// In-content header of the tools list itself: glass back button + title,
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
#endif

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

struct ToolPlaceholderView: View {
    let tool: Tool

    // Chrome (title, back) is owned by the hosting container on every
    // platform: the macOS detail column and the iOS navigation stacks.
    var body: some View {
        ContentUnavailableView {
            Label(tool.titleKey, systemImage: tool.icon)
        } description: {
            Text("tools.placeholder")
        }
        .detailPageTitle(tool.titleKey)
    }
}
