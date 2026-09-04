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

/// Enter/leave direction of a drill swap; neutral is the plain page cross-fade.
private enum SwapDirection {
    case neutral, push, pop
}

/// Detail-column page host with a TG-style swap: the container's identity never
/// changes, each page lives in its own NSHostingController (its own view graph),
/// and switching pages is a plain subview swap — the window chrome and the
/// enclosing SwiftUI graph are not touched.
struct DetailPageHost: NSViewControllerRepresentable {
    let page: DetailPage
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chrome: DetailChrome
    @EnvironmentObject private var drill: ConnectionDrill

    func makeNSViewController(context: Context) -> DetailPageViewController {
        DetailPageViewController(page: page, model: model, chrome: chrome, drill: drill)
    }

    func updateNSViewController(_ controller: DetailPageViewController, context: Context) {
        controller.show(page)
    }
}

final class DetailPageViewController: NSViewController {
    private let model: AppModel
    private let chrome: DetailChrome
    private let drill: ConnectionDrill
    private var page: DetailPage
    private var pages: [DetailPage: NSHostingController<AnyView>] = [:]
    private weak var currentView: NSView?
    private weak var currentPage: NSHostingController<AnyView>?

    init(page: DetailPage, model: AppModel, chrome: DetailChrome, drill: ConnectionDrill) {
        self.page = page
        self.model = model
        self.chrome = chrome
        self.drill = drill
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController(for: page))
        currentPage = pages[page]
        show(page)
    }

    func show(_ newPage: DetailPage) {
        guard isViewLoaded else { return }
        guard newPage != page || currentView == nil else { return }
        let isInitial = currentView == nil

        let direction: SwapDirection
        switch (page, newPage) {
        case (.section, .connectionDetail):
            direction = .push
        // Pop only when returning to the drill's own list; jumping straight to
        // another section is a plain page switch.
        case (.connectionDetail, .section(let section)):
            direction = section == .connection ? .pop : .neutral
        default:
            direction = .neutral
        }
        page = newPage

        let page = hostingController(for: newPage)
        let newView = page.view
        newView.frame = view.bounds
        newView.autoresizingMask = [.width, .height]

        let oldView = currentView
        let oldPage = currentPage

        // Containment follows visibility: more than one child hosting controller
        // makes every cached page bridge its title/toolbar/search into the shared
        // window toolbar at once (wrong titles, duplicate search field → crash).
        if oldPage !== page {
            oldPage?.removeFromParent()
            if page.parent !== self {
                addChild(page)
            }
        }

        // On pop the incoming page goes UNDER the outgoing one: the detail
        // slides away over the list, not the other way around.
        if newView.superview !== view {
            if direction == .pop, let oldView {
                view.addSubview(newView, positioned: .below, relativeTo: oldView)
            } else {
                view.addSubview(newView)
            }
        }
        currentView = newView
        currentPage = page

        // All transitions run on the layer (GPU compositing — no SwiftUI
        // re-layout) and sidestep the bitmap-snapshot color dip that killed the
        // earlier cross-fade attempt. The old page stays until the animation
        // completes: translucent pages cross-fade against it naturally.
        let animate = !isInitial && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = direction == .neutral ? 0.22 : 0.25
        // Neutral page switches fade + rise; drill-ins slide horizontally like a
        // navigation push/pop, with a slight counter-slide on the leaving page.
        let newFromX: CGFloat = direction == .push ? 48 : (direction == .pop ? -16 : 0)
        let newFromY: CGFloat = direction == .neutral ? 10 : 0
        let oldToX: CGFloat = direction == .push ? -16 : (direction == .pop ? 48 : 0)
        if animate, let layer = newView.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let slide = CABasicAnimation(keyPath: "transform.translation")
            slide.fromValue = CGPoint(x: newFromX, y: newFromY)
            slide.toValue = CGPoint.zero

            let group = CAAnimationGroup()
            group.animations = [fade, slide]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = true
            layer.add(group, forKey: "pageTransition")
        }
        // Symmetric fade-out: translucent pages (glass cards) would otherwise let
        // the old page show through the incoming one for the whole animation.
        if animate, let oldView, oldView !== newView, let oldLayer = oldView.layer {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1
            fadeOut.toValue = 0

            let slideOut = CABasicAnimation(keyPath: "transform.translation")
            slideOut.fromValue = CGPoint.zero
            slideOut.toValue = CGPoint(x: oldToX, y: 0)

            let group = CAAnimationGroup()
            group.animations = [fadeOut, slideOut]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = true
            oldLayer.add(group, forKey: "pageTransition")
        }

        guard oldView !== newView else { return }
        if let oldView {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                // Only remove if it hasn't become visible again meanwhile.
                if oldView !== self.currentView {
                    oldView.removeFromSuperview()
                }
            }
        }
    }

    // Pages are cached after their first build: revisiting re-attaches the existing
    // view instead of rebuilding the view graph.
    private func hostingController(for page: DetailPage) -> NSHostingController<AnyView> {
        if let cached = pages[page] { return cached }
        let content: AnyView
        switch page {
        case .section(let section):
            content = AnyView(FeatureDetailView(section: section))
        case .connectionDetail(let activity):
            content = AnyView(ConnectionDetailView(activity: activity))
        }
        let host = NSHostingController(
            rootView: AnyView(
                content
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
            )
        )
        host.sizingOptions = []
        // Layer backing enables GPU-composited transition animations.
        host.view.wantsLayer = true
        pages[page] = host
        return host
    }
}
#endif
