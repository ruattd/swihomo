import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Page-root navigation container. Everywhere except the iOS compact tab layout
/// this is a plain NavigationStack. In the compact layout the outer stack (which
/// wraps the TabView) already provides navigation — a nested NavigationStack as
/// pushed content gets silently popped by SwiftUI, and the desynced path makes
/// the NEXT push crash with AnyNavigationPath.comparisonTypeMismatch.
struct PageNavigationStack<Content: View>: View {
    #if os(iOS)
    @Environment(\.pushCompactRoute) private var pushCompactRoute
    #endif
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        if pushCompactRoute != nil {
            content
        } else {
            NavigationStack { content }
        }
        #else
        NavigationStack { content }
        #endif
    }
}

extension View {
    /// Page navigation title — iOS only. On macOS the detail container owns the
    /// window title; titles declared inside nested hosting controllers bridge into
    /// the shared window titlebar unpredictably (wrong/flickering titles).
    @ViewBuilder
    func detailPageTitle(_ key: LocalizedStringKey) -> some View {
        #if os(iOS)
        navigationTitle(Text(key))
        #else
        self
        #endif
    }
}

#if os(macOS)
struct WindowToolbarBaselineHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarBaselineView {
        ToolbarBaselineView()
    }

    func updateNSView(_ nsView: ToolbarBaselineView, context: Context) {
        nsView.hideToolbarBaseline()
    }
}

final class ToolbarBaselineView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideToolbarBaseline()
    }

    func hideToolbarBaseline() {
        // The SwiftUI navigation toolbar is attached after this background view.
        DispatchQueue.main.async { [weak self] in
            self?.window?.toolbar?.showsBaselineSeparator = false
        }
    }
}
#endif

#if os(macOS)
enum DockIconVisibility {
    static func update(showsMenuBar: Bool, hidesDockIcon: Bool) {
        NSApplication.shared.setActivationPolicy(showsMenuBar && hidesDockIcon ? .accessory : .regular)
    }

    static func activateWindowIfNeeded(showsMenuBar: Bool, hidesDockIcon: Bool) {
        guard showsMenuBar && hidesDockIcon else { return }

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        }
    }
}
#endif
