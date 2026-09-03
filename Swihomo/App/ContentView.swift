import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appTheme") private var selectedTheme = AppTheme.system.rawValue
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    #if os(macOS)
    @AppStorage("hidesDockIcon") private var hidesDockIcon = false
    #endif

    private var preferredColorScheme: ColorScheme? {
        AppTheme(rawValue: selectedTheme)?.colorScheme
    }

    #if os(macOS)
    // macOS navigates by swapping the detail column; pushing destinations inside
    // the sidebar column tears down the whole home grid on every page switch.
    @State private var activeSection: HomeSection = .connection
    #endif

    var body: some View {
        NavigationSplitView {
            #if os(macOS)
            HomeView(activeSection: $activeSection)
                .navigationSplitViewColumnWidth(min: 310, ideal: 310, max: 516)
                .frame(minWidth: 310)
            #else
            HomeView()
                .navigationSplitViewColumnWidth(min: 310, ideal: 310, max: 516)
                .navigationDestination(for: HomeSection.self) { section in
                    FeatureDetailView(section: section)
                }
            #endif
        } detail: {
            #if os(macOS)
            FeatureDetailView(section: activeSection)
                // Fresh identity per section → the opacity transition runs on swap;
                // the selection setter wraps the change in withAnimation.
                .id(activeSection)
                .transition(.opacity)
            #else
            FeatureDetailView(section: .connection)
            #endif
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        #if os(macOS)
        .background(WindowToolbarBaselineHider())
        #endif
        .overlay(alignment: .bottom) {
            if let error = model.errorMessage {
                ErrorBanner(message: error, dismiss: { model.dismissError() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: model.errorMessage)
        #if os(macOS)
        .onAppear {
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
            DockIconVisibility.activateWindowIfNeeded(
                showsMenuBar: showsMenuBar,
                hidesDockIcon: hidesDockIcon
            )
        }
        .onChange(of: showsMenuBar) { _, _ in
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
        }
        .onChange(of: hidesDockIcon) { _, _ in
            DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
        }
        #endif
    }
}
