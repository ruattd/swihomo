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
    // One stable window chrome; pages register their toolbar/search content here.
    @StateObject private var detailChrome = DetailChrome()
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
            // Imperative page swaps inside a stable container whose identity never
            // changes. The window chrome (title, toolbar, search) is declared HERE,
            // once, by the container — pages register their actions via
            // DetailChrome instead of bridging their own .toolbar/.searchable from
            // nested hosting controllers (which collided in the shared NSToolbar).
            // Only the toolbar's *items* swap on page change; the shell persists.
            let entry = detailChrome.entries[activeSection]
            NavigationStack {
                DetailPageHost(section: activeSection)
                    .environmentObject(detailChrome)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Reference-probed (HEAD): the liquid glass is the detail
                    // column's own NSScrollPocket, active only when the page's
                    // scroll view physically extends into the 52pt titlebar zone.
                    // The representable is laid out below that zone unless the
                    // safe area is ignored here (titlebar transparency is NOT
                    // involved — the working build has it off).
                    .ignoresSafeArea(.container, edges: .top)
                    .navigationTitle(Text(activeSection.titleKey))
                    .toolbar {
                        if let toolbar = entry?.toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                toolbar()
                            }
                        }
                        // .searchable never attaches through the representable
                        // boundary (probed: no search item in the toolbar), so the
                        // search field is an explicit toolbar item instead.
                        if let searchText = entry?.searchText, let prompt = entry?.searchPrompt {
                            ToolbarItem(placement: .primaryAction) {
                                TextField(prompt, text: searchText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                        }
                    }
            }
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
