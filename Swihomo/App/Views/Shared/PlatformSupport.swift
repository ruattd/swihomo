import SwiftUI
#if os(macOS)
import AppKit
#endif

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
