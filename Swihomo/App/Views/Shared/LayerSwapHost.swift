#if os(macOS)
import AppKit
import SwiftUI

/// Enter/leave direction of a layer swap; neutral is the plain cross-fade.
enum LayerSwapDirection {
    case neutral, push, pop
}

/// Generic page host with a GPU-composited swap: each page lives in its own
/// NSHostingController (its own view graph) and switching pages animates the
/// backing LAYERS only — transform and opacity — so there is no SwiftUI
/// re-layout and no bitmap rasterization. Glass-heavy pages swap without
/// dropping frames, unlike SwiftUI .transition which re-renders both trees
/// every frame.
///
/// Push/pop replicate the iOS navigation stack: the incoming page slides in
/// over the outgoing one on a near-critically-damped spring (springy velocity
/// curve, no visible overshoot), while the outgoing page parallax-slides a
/// quarter width underneath. Neutral cross-fades with a slight rise, like the
/// detail column's switches.
///
/// Pages stay transparent: the split view column's own glass background shows
/// through exactly as it does without this host. Because glass pages are
/// see-through, the UNDERNEATH page wears a mask that tracks the top page's
/// leading edge — the mask springs with the same parameters, so it stays in
/// perfect sync — and the bottom page never bleeds through the top one.
///
/// Usage:
///     LayerSwapHost(selection: drilled, direction: drilled ? .push : .pop) { isDrilled in
///         if isDrilled { DetailView() } else { ListView() }
///     }
struct LayerSwapHost<Selection: Hashable, Content: View>: NSViewControllerRepresentable {
    let selection: Selection
    let direction: LayerSwapDirection
    @ViewBuilder let content: (Selection) -> Content

    // Hosting controllers do NOT inherit the SwiftUI environment on their own;
    // capture it whole (EnvironmentObject included) and re-apply per page.
    @Environment(\.self) private var environment

    func makeNSViewController(context: Context) -> LayerSwapViewController<Selection, Content> {
        let controller = LayerSwapViewController(selection: selection, content: content)
        controller.environment = environment
        return controller
    }

    func updateNSViewController(_ controller: LayerSwapViewController<Selection, Content>, context: Context) {
        // Hosting controllers do not track the SwiftUI environment on their
        // own, and pages are CACHED — without this, a theme/appearance change
        // never reaches an already-built page (stale glass rendering until the
        // page is destroyed). Re-applying the root view is diffed by SwiftUI,
        // so state survives and unchanged content costs ~nothing.
        controller.environment = environment
        controller.reapplyEnvironment()
        controller.show(selection, direction: direction)
    }
}

final class LayerSwapViewController<Selection: Hashable, Content: View>: NSViewController {
    var environment: EnvironmentValues?

    private let content: (Selection) -> Content
    private(set) var selection: Selection
    private var pages: [Selection: NSHostingController<AnyView>] = [:]
    private weak var currentView: NSView?
    private weak var currentPage: NSHostingController<AnyView>?

    init(selection: Selection, content: @escaping (Selection) -> Content) {
        self.selection = selection
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
        // Sliding pages travel past the container edge; clip so they never
        // paint over the neighbouring column.
        view.wantsLayer = true
        view.layer?.masksToBounds = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController(for: selection))
        currentPage = pages[selection]
        show(selection, direction: .neutral)
    }

    func show(_ new: Selection, direction: LayerSwapDirection) {
        guard isViewLoaded else { return }
        guard new != selection || currentView == nil else { return }
        let isInitial = currentView == nil
        selection = new

        let page = hostingController(for: new)
        let newView = page.view
        newView.frame = view.bounds
        newView.autoresizingMask = [.width, .height]

        let oldView = currentView
        let oldPage = currentPage

        // Containment follows visibility: more than one child hosting controller
        // makes every cached page bridge its title/toolbar into the shared
        // window chrome at once (wrong titles, duplicate items).
        if oldPage !== page {
            oldPage?.removeFromParent()
            if page.parent !== self {
                addChild(page)
            }
        }

        // iOS stacking: on push the incoming page covers the outgoing one; on
        // pop the incoming page slides back in UNDER the departing page.
        if newView.superview !== view {
            if direction == .pop, let oldView {
                view.addSubview(newView, positioned: .below, relativeTo: oldView)
            } else {
                view.addSubview(newView)
            }
        }
        currentView = newView
        currentPage = page

        // Reset model values first: a cached page may still carry the end state
        // of its last exit animation, and without a reset the presentation
        // layer snaps back to it for one frame when the animation completes.
        if let layer = newView.layer {
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            layer.mask = nil
        }

        let animate = !isInitial && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let width = view.bounds.width
        // iOS push geometry: the incoming page travels the full width over the
        // old one; the outgoing page parallax-slides only a quarter width.
        let newFromX: CGFloat = direction == .push ? width : (direction == .pop ? -width / 4 : 0)
        let oldToX: CGFloat = direction == .push ? -width / 4 : (direction == .pop ? width : 0)

        var duration: CFTimeInterval = 0.22
        if animate, let layer = newView.layer {
            if direction == .neutral {
                // Neutral keeps the detail column's fade + rise.
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                let rise = CABasicAnimation(keyPath: "transform.translation")
                rise.fromValue = CGPoint(x: 0, y: 10)
                rise.toValue = CGPoint.zero
                let group = CAAnimationGroup()
                group.animations = [fade, rise]
                group.duration = duration
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                group.isRemovedOnCompletion = true
                layer.add(group, forKey: "pageTransition")
            } else {
                let slide = Self.flightSpring(keyPath: "transform.translation.x")
                slide.fromValue = newFromX
                slide.toValue = CGFloat.zero
                layer.add(slide, forKey: "pageTransition")
                duration = slide.settlingDuration
            }
        }
        if animate, let oldView, oldView !== newView, let oldLayer = oldView.layer {
            // Model value goes to the END state up front: with the animation
            // removed on completion, the presentation layer would otherwise
            // snap back to the model (the pre-animation layout) for one frame
            // before the view is removed — the visible "flash".
            if direction == .neutral {
                oldLayer.opacity = 0
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1
                fadeOut.toValue = 0
                fadeOut.duration = duration
                fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
                fadeOut.isRemovedOnCompletion = true
                oldLayer.add(fadeOut, forKey: "pageTransition")
            } else {
                oldLayer.transform = CATransform3DMakeTranslation(oldToX, 0, 0)
                let slideOut = Self.flightSpring(keyPath: "transform.translation.x")
                slideOut.fromValue = CGFloat.zero
                slideOut.toValue = oldToX
                oldLayer.add(slideOut, forKey: "pageTransition")
                duration = max(duration, slideOut.settlingDuration)
            }
        }

        // Mask the UNDERNEATH page to the region the top page has not covered
        // yet: glass pages are transparent, so without the mask the bottom
        // page would bleed through the top one mid-flight. The mask springs
        // with the same parameters as the page slides, so its edge tracks the
        // top page's leading edge exactly; its position compensates for the
        // bottom page's own parallax translation.
        if animate, direction == .push, let oldView, let oldLayer = oldView.layer {
            Self.applyFlightMask(
                to: oldLayer, height: oldView.bounds.height,
                fromPosition: 0, fromWidth: width,
                toPosition: width / 4, toWidth: 0
            )
        }
        if animate, direction == .pop, let layer = newView.layer {
            Self.applyFlightMask(
                to: layer, height: newView.bounds.height,
                fromPosition: width / 4, fromWidth: 0,
                toPosition: 0, toWidth: width
            )
            // The reveal ends at the full rect; drop the mask afterwards so a
            // column resize later cannot be clipped by a stale mask.
            let appliedMask = layer.mask
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if layer.mask === appliedMask {
                    layer.mask = nil
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Only remove if it hasn't become visible again meanwhile.
            if let oldView, oldView !== newView, oldView !== self.currentView {
                oldView.removeFromSuperview()
            }
        }
    }

    // Nearly critically damped (zeta ~0.92): the spring keeps its ease-out
    // velocity curve, but overshoot stays under half a point — an underdamped
    // spring would swing the incoming page past its final position and expose
    // the page beneath along the trailing edge.
    private static func flightSpring(keyPath: String) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = 300
        spring.damping = 32
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = true
        return spring
    }

    /// Masks `layer` to a rect whose left edge and width spring from/to the
    /// given values, in the layer's own coordinate space. Model values are set
    /// to the end state up front (no snap-back when the animations complete).
    private static func applyFlightMask(
        to layer: CALayer, height: CGFloat,
        fromPosition: CGFloat, fromWidth: CGFloat,
        toPosition: CGFloat, toWidth: CGFloat
    ) {
        let mask = CALayer()
        // The mask clips by ALPHA: a bare CALayer is fully transparent and
        // would hide the page entirely, so give it an opaque fill.
        mask.backgroundColor = NSColor.black.cgColor
        mask.anchorPoint = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = CGRect(x: toPosition, y: 0, width: toWidth, height: height)
        CATransaction.commit()
        layer.mask = mask

        let slide = flightSpring(keyPath: "position.x")
        slide.fromValue = fromPosition
        slide.toValue = toPosition
        mask.add(slide, forKey: "maskSlide")

        let shrink = flightSpring(keyPath: "bounds.size.width")
        shrink.fromValue = fromWidth
        shrink.toValue = toWidth
        mask.add(shrink, forKey: "maskShrink")
    }

    /// Re-applies the current environment to every cached page. Hosting
    /// controllers do not observe SwiftUI environment changes; without this a
    /// theme/appearance switch would only reach pages built AFTER the change.
    func reapplyEnvironment() {
        guard let environment else { return }
        for (selection, host) in pages {
            host.rootView = AnyView(content(selection).environment(\.self, environment))
        }
    }

    // Pages are cached after their first build: revisiting re-attaches the
    // existing view (keeping scroll position and state) instead of rebuilding.
    private func hostingController(for selection: Selection) -> NSHostingController<AnyView> {
        if let cached = pages[selection] { return cached }
        var root = AnyView(content(selection))
        if let environment {
            root = AnyView(root.environment(\.self, environment))
        }
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        // Layer backing enables GPU-composited transition animations.
        host.view.wantsLayer = true

        pages[selection] = host
        return host
    }
}
#endif
