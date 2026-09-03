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

/// Detail-column page host with a TG-style swap: the container's identity never
/// changes, each page lives in its own NSHostingController (its own view graph),
/// and switching pages is a plain subview swap — the window chrome and the
/// enclosing SwiftUI graph are not touched.
struct DetailPageHost: NSViewControllerRepresentable {
    let section: HomeSection
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var chrome: DetailChrome

    func makeNSViewController(context: Context) -> DetailPageViewController {
        DetailPageViewController(section: section, model: model, chrome: chrome)
    }

    func updateNSViewController(_ controller: DetailPageViewController, context: Context) {
        controller.show(section)
    }
}

final class DetailPageViewController: NSViewController {
    private let model: AppModel
    private let chrome: DetailChrome
    private var section: HomeSection
    private var pages: [HomeSection: NSHostingController<AnyView>] = [:]
    private weak var currentView: NSView?
    private weak var currentPage: NSHostingController<AnyView>?

    init(section: HomeSection, model: AppModel, chrome: DetailChrome) {
        self.section = section
        self.model = model
        self.chrome = chrome
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
        addChild(hostingController(for: section))
        currentPage = pages[section]
        show(section)
    }

    func show(_ newSection: HomeSection) {
        guard isViewLoaded else { return }
        guard newSection != section || currentView == nil else { return }
        let isInitial = currentView == nil
        section = newSection

        let page = hostingController(for: newSection)
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

        if newView.superview !== view {
            view.addSubview(newView)
        }
        currentView = newView
        currentPage = page

        // Fade + slight rise on the incoming page, animated on the layer (GPU
        // compositing — no SwiftUI re-layout). The old page stays until the
        // animation completes: the incoming page's translucency cross-fades
        // against it naturally. Layer animation also sidesteps the bitmap-
        // snapshot color dip that killed the earlier cross-fade attempt.
        let animate = !isInitial && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate, let layer = newView.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 10
            rise.toValue = 0

            let group = CAAnimationGroup()
            group.animations = [fade, rise]
            group.duration = 0.22
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
            fadeOut.duration = 0.22
            fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fadeOut.isRemovedOnCompletion = true
            oldLayer.add(fadeOut, forKey: "pageTransition")
        }

        guard oldView !== newView else { return }
        if let oldView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // Only remove if it hasn't become visible again meanwhile.
                if oldView !== self.currentView {
                    oldView.removeFromSuperview()
                }
            }
        }
    }

    // Pages are cached after their first build: revisiting re-attaches the existing
    // view instead of rebuilding the view graph.
    private func hostingController(for section: HomeSection) -> NSHostingController<AnyView> {
        if let cached = pages[section] { return cached }
        let host = NSHostingController(
            rootView: AnyView(
                FeatureDetailView(section: section)
                    .environmentObject(model)
                    .environmentObject(chrome)
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
        pages[section] = host
        return host
    }
}
#endif
