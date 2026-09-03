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

    var body: some View {
        NavigationSplitView {
            HomeView()
                .navigationSplitViewColumnWidth(min: 310, ideal: 310, max: 516)
                #if os(macOS)
                .frame(minWidth: 310)
                #endif
                .navigationDestination(for: HomeSection.self) { section in
                    FeatureDetailView(section: section)
                }
        } detail: {
            FeatureDetailView(section: .connection)
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
