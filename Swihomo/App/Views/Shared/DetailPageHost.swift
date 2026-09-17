#if os(macOS)
import AppKit
import SwiftUI

/// Hoisted window chrome for detail pages. Every page declaring its own
/// .toolbar/.searchable inside a nested hosting controller bridges into the SAME
/// window toolbar and collides (mixed items, duplicate search field crashes), so
/// pages register their chrome here and the container owns one stable toolbar.
final class DetailChrome: ObservableObject {
    struct Entry {
        var toolbar: (() -> AnyView)?
        var searchText: Binding<String>?
        var searchPrompt: LocalizedStringKey?
    }

    @Published private(set) var entries: [HomeSection: Entry] = [:]

    func register(_ section: HomeSection, entry: Entry) {
        entries[section] = entry
    }
}

/// Zero-size registration point placed in a page's body (macOS only).
struct ChromeProvider: View {
    let section: HomeSection
    var toolbar: (() -> AnyView)?
    var searchText: Binding<String>?
    var searchPrompt: LocalizedStringKey?

    @EnvironmentObject private var chrome: DetailChrome

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                chrome.register(
                    section,
                    entry: .init(toolbar: toolbar, searchText: searchText, searchPrompt: searchPrompt)
                )
            }
    }
}

/// macOS connection drill-in state, shared between DashboardView (sets it on
/// selection) and the detail-column container (swaps page + chrome on it).
/// Drilling is a container-level page, so the window title/toolbar/search
/// switch too — an in-place swap inside the connections page cannot do that.
final class ConnectionDrill: ObservableObject {
    @Published var activity: MihomoConnectionActivity?
}

/// Detail-column page identity: a home section, or the connection drill-in.
enum DetailPage: Hashable {
    case section(HomeSection)
    case connectionDetail(MihomoConnectionActivity)
}

/// Detail-column page host on top of LayerSwapViewController: the container's
/// identity never changes and page swaps animate the backing layers only, so
/// the window chrome and the enclosing SwiftUI graph are not touched. The
/// connection drill-in uses the same iOS-style stack push/pop as the tools
/// sidebar swap.
struct DetailPageHost: NSViewControllerRepresentable {
    let page: DetailPage
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chrome: DetailChrome
    @EnvironmentObject private var drill: ConnectionDrill
    // Hosting controllers do NOT inherit the SwiftUI environment on their own;
    // capture it whole (EnvironmentObject included) and hand it to the
    // controller, which re-applies it per page — without this, a theme switch
    // never reaches an already-cached page.
    @Environment(\.self) private var environment

    func makeNSViewController(context: Context) -> LayerSwapViewController<DetailPage, AnyView> {
        let controller = LayerSwapViewController(selection: page) { page in
            AnyView(pageContent(for: page))
        }
        controller.environment = environment
        return controller
    }

    func updateNSViewController(_ controller: LayerSwapViewController<DetailPage, AnyView>, context: Context) {
        controller.environment = environment
        controller.reapplyEnvironment()
        controller.show(page, direction: direction(to: page, from: controller.selection))
    }

    /// Push when drilling into a connection; pop only when returning to the
    /// drill's own list — jumping straight to another section is a plain page
    /// switch.
    private func direction(to newPage: DetailPage, from oldPage: DetailPage) -> LayerSwapDirection {
        switch (oldPage, newPage) {
        case (.section, .connectionDetail):
            .push
        case (.connectionDetail, .section(let section)):
            section == .connection ? .pop : .neutral
        default:
            .neutral
        }
    }

    private func pageContent(for page: DetailPage) -> some View {
        let content: AnyView
        switch page {
        case .section(let section):
            content = AnyView(FeatureDetailView(section: section))
        case .connectionDetail(let activity):
            content = AnyView(ConnectionDetailView(activity: activity))
        }
        return content
            .environmentObject(model)
            .environmentObject(chrome)
            .environmentObject(drill)
            // The column hosting view inherits the window's 52pt titlebar/
            // toolbar zone as top safe area, which stops page lists from
            // reaching under the toolbar — and no underlap means the
            // liquid-glass scroll pocket never activates. The page content
            // re-adds the same height as a plain inset (starting below the
            // glass), then the whole assembly ignores the inherited zone —
            // order matters: ignoresSafeArea would otherwise swallow the
            // inset too.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 52)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .top)
    }
}
#endif
