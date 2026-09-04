import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
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
    #if os(iOS)
    /// Outer-stack path of the compact tab layout (sections + connection
    /// drill-in). One typed path, one `for:` destination, no item-based
    /// destinations anywhere inside — mixing them crashes SwiftUI with
    /// AnyNavigationPath.comparisonTypeMismatch.
    @State private var compactPath: [CompactRoute] = []
    /// Selected tab in the compact layout; the outer stack reads its title
    /// (TabView is opaque to it, so per-page titles can't bubble out).
    @State private var compactTab = CompactTab.home
    #endif

    var body: some View {
        rootContent
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
                DockIconVisibility.activateWindowIfNeeded(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
            }
            .onChange(of: showsMenuBar) { _, _ in
                DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
            }
            .onChange(of: hidesDockIcon) { _, _ in
                DockIconVisibility.update(showsMenuBar: showsMenuBar, hidesDockIcon: hidesDockIcon)
            }
            #endif
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        splitContent
        #else
        // Bottom tabs are compact-width only and iOS 18+; older iOS keeps the
        // traditional split layout even on narrow screens.
        if horizontalSizeClass == .compact, #available(iOS 18.0, *) {
            compactTabs
        } else {
            splitContent
        }
        #endif
    }

    #if os(iOS)
    /// Compact-width layout: bottom tabs instead of the sidebar. Home drops the
    /// proxies card (it becomes a tab) and preferences/about (tab 3 + its icon).
    private enum CompactTab: Hashable {
        case home, proxies, preferences

        var titleKey: LocalizedStringKey {
            switch self {
            // Matches HomeView's iOS title: the app name, not "Home".
            case .home: "Swihomo"
            case .proxies: HomeSection.proxies.titleKey
            case .preferences: HomeSection.preference.titleKey
            }
        }
    }

    /// The stack wraps the tabs, so pushes cover the whole tab interface: the
    /// tab bar rides the standard push transition instead of snapping hidden.
    @available(iOS 18.0, *)
    private var compactTabs: some View {
        NavigationStack(path: $compactPath) {
            TabView(selection: $compactTab) {
                Tab("navigation.home", systemImage: "house", value: .home) {
                    HomeView()
                }
                Tab(HomeSection.proxies.titleKey, systemImage: HomeSection.proxies.icon, value: .proxies) {
                    ProxiesView()
                }
                Tab(HomeSection.preference.titleKey, systemImage: HomeSection.preference.icon, value: .preferences) {
                    PreferencesView()
                }
            }
            .navigationTitle(compactTab.titleKey)
            // The about entry lives on the outer stack's bar: toolbar items on
            // TabView content don't propagate through the tab boundary either.
            .toolbar {
                if compactTab == .preferences {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            compactPath.append(.section(.about))
                        } label: {
                            Image(systemName: HomeSection.about.icon)
                        }
                    }
                }
            }
            .navigationDestination(for: CompactRoute.self) { route in
                switch route {
                case .section(let section):
                    FeatureDetailView(section: section)
                case .connection(let activity):
                    ConnectionDetailView(activity: activity)
                }
            }
        }
        // Attached ABOVE the stack: custom environment values set on the TabView
        // inside never reach navigationDestination content (probed).
        .environment(\.pushCompactRoute) { compactPath.append($0) }
    }
    #endif

    private var splitContent: some View {
        NavigationSplitView {
            #if os(macOS)
            HomeView(activeSection: $activeSection)
                .navigationSplitViewColumnWidth(min: 310, ideal: 310, max: 516)
                .frame(minWidth: 310)
            #else
            HomeView()
                .navigationSplitViewColumnWidth(min: 310, ideal: 310, max: 516)
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
    }
}
