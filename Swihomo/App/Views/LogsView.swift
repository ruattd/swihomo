import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private enum LogFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case app
    case core

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .app: "App"
        case .core: "Core"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "common.all"
        case .app: "common.app"
        case .core: "common.core"
        }
    }
}

private enum LogLevelFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All levels"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "logs.allLevels"
        case .debug: "common.debug"
        case .info: "common.info"
        case .warning: "common.warning"
        case .error: "common.error"
        }
    }

    var level: LogLevel? {
        LogLevel(rawValue: rawValue)
    }
}

struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = LogFilter.all
    @State private var levelFilter = LogLevelFilter.all
    @State private var searchText = ""
    @State private var visibleEntries: [LogEntry] = []
    @State private var showingClearLogsConfirmation = false

    /// Increment to force the list back to the latest entries (the toolbar's
    /// return-to-bottom button); the follower re-arms on the new value.
    @State private var followRequest = 0

    // Body re-evaluates on every AppModel publish (traffic 1/s) because the page stays cached,
    // so the filter pipeline must not run in body.
    // model.logEntries is already chronological (PersistentLogStore maintains
    // ascending order), so display order needs no sort: newest entries append at
    // the bottom. With no filters active the array assigns directly — it is
    // copy-on-write, so the common path is O(1).
    private func recomputeEntries() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filter != .all || levelFilter != .all || !query.isEmpty else {
            visibleEntries = model.logEntries
            return
        }
        visibleEntries = model.logEntries
            .filter { filter == .all || $0.source.rawValue == filter.rawValue }
            .filter { levelFilter.level == nil || $0.level == levelFilter.level }
            .filter { entry in
                guard !query.isEmpty else { return true }
                return [entry.module, entry.message, entry.source.displayName, entry.level.displayName]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
    }
    var body: some View {
        PageNavigationStack {
            List {
                ForEach(visibleEntries) { entry in
                    LogEntryRow(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .contentCard()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }
            .listStyle(.plain)
            // Instant inserts: bursts of appended rows must not animate — a frame
            // animation moves content under the reader and fights the tail follow.
            .transaction { $0.animation = nil }
            // Rows append at the bottom, so the reading position is preserved by
            // construction; the follower only jumps to the bottom when the view
            // already rests there or a jump is explicitly requested. Overlay, not
            // background: List drops background representables entirely.
            .overlay(alignment: .top) {
                LogTailFollower(followRequest: followRequest)
                    .frame(width: 0, height: 0)
            }
            .overlay {
                if visibleEntries.isEmpty {
                    ContentUnavailableView(
                        LocalizedStringKey("logs.empty"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(LocalizedStringKey("logs.empty.description"))
                    )
                }
            }
            .detailPageTitle("navigation.logs")
            #if os(macOS)
            // Chrome is hoisted to the detail container; per-page .toolbar/.searchable
            // inside nested hosting controllers collide in the shared window toolbar.
            .background(ChromeProvider(
                section: .logs,
                toolbar: {
                    AnyView(LogsToolbarContent(
                        filter: $filter,
                        levelFilter: $levelFilter,
                        showingClearLogsConfirmation: $showingClearLogsConfirmation,
                        onReturnToBottom: { followRequest += 1 }
                    ))
                },
                searchText: $searchText,
                searchPrompt: "logs.search"
            ))
            #else
            .searchable(text: $searchText, prompt: "logs.search")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    LogsToolbarContent(
                        filter: $filter,
                        levelFilter: $levelFilter,
                        showingClearLogsConfirmation: $showingClearLogsConfirmation,
                        onReturnToBottom: { followRequest += 1 }
                    )
                }
            }
            #endif
            .confirmationDialog(
                Text(LocalizedStringKey("logs.clearLogs.confirmationTitle")),
                isPresented: $showingClearLogsConfirmation,
                titleVisibility: .visible
            ) {
                Button("logs.clearApp", role: .destructive) {
                    Task { await model.clearLogs(source: .app) }
                }
                Button("logs.clearCore", role: .destructive) {
                    Task { await model.clearLogs(source: .core) }
                }
                Button("logs.clearAll", role: .destructive) {
                    Task { await model.clearLogs() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("logs.clearLogs.description"))
            }
            .task { await model.reloadLogs() }
            .onAppear { recomputeEntries() }
            .onChange(of: model.logEntries) { _ in recomputeEntries() }
            .onChange(of: filter) { _ in recomputeEntries() }
            .onChange(of: levelFilter) { _ in recomputeEntries() }
            .onChange(of: searchText) { _ in recomputeEntries() }
        }
    }

}

// Toolbar content for the logs page, rendered by the container on macOS (via
// ChromeProvider) and in-page on iOS.
private struct LogsToolbarContent: View {
    @Binding var filter: LogFilter
    @Binding var levelFilter: LogLevelFilter
    @Binding var showingClearLogsConfirmation: Bool
    let onReturnToBottom: () -> Void

    var body: some View {
        Menu {
            sourceFilterSection
            levelFilterSection
        } label: {
            Label(filter.titleKey, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.medium))
        }

        Menu {
            Button {
                onReturnToBottom()
            } label: {
                Label("logs.returnToBottom", systemImage: "arrow.down.to.line")
            }
            Button(role: .destructive) {
                showingClearLogsConfirmation = true
            } label: {
                Label("logs.clearLogs", systemImage: "trash")
            }
        } label: {
            Label("common.more", systemImage: "ellipsis.circle")
        }
    }

    private var sourceFilterSection: some View {
        Section("common.source") {
            ForEach(LogFilter.allCases) { source in
                // macOS 27 hides menu item symbol images by default; the checkmark
                // glyphs carry selection state, so opt the items back into icons.
                Button {
                    filter = source
                } label: {
                    Label(
                        source.titleKey,
                        systemImage: filter == source ? "checkmark" : "circle"
                    )
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private var levelFilterSection: some View {
        Section("common.level") {
            ForEach(LogLevelFilter.allCases) { level in
                Button {
                    levelFilter = level
                } label: {
                    Label(
                        level.titleKey,
                        systemImage: levelFilter == level ? "checkmark" : "circle"
                    )
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(entry.source.localizationKey))
                    .textCase(.uppercase)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(entry.source == .app ? .blue : .teal)
                Text("[\(entry.module)]")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(entry.level.localizationKey))
                    .textCase(.uppercase)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(levelColor)
            }
            Text(entry.message)
                .font(messageFont)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    // callout (16pt) reads oversized for dense console lines on a phone; caption (12pt)
    // matches the timestamp line above it.
    private var messageFont: Font {
        #if os(macOS)
        .callout.monospaced()
        #else
        .caption.monospaced()
        #endif
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }
}

/// Pins the log list to the latest entries while it rests at the bottom.
/// Rows append at the bottom, so growth never moves what the user is reading
/// and no offset compensation is needed — the follower only re-asserts the
/// bottom edge when the view is already there. Programmatic offset changes
/// cancel UIScrollView deceleration, which is exactly why this MUST NOT fire
/// mid-fling: it never touches the offset unless the view is at rest at the
/// bottom, so scroll momentum survives.
private struct LogTailFollower: View {
    /// Increment to force a jump to the bottom (return-to-bottom button);
    /// also re-arms following.
    let followRequest: Int

    var body: some View {
        #if os(iOS)
        UIKitFollower(followRequest: followRequest)
        #else
        AppKitFollower(followRequest: followRequest)
        #endif
    }

    #if os(iOS)
    private struct UIKitFollower: UIViewRepresentable {
        let followRequest: Int

        func makeUIView(context: Context) -> FollowerView {
            FollowerView()
        }

        func updateUIView(_ uiView: FollowerView, context: Context) {
            uiView.handleFollowRequest(followRequest)
        }

        fileprivate final class FollowerView: UIView {
            private var offsetObservation: NSKeyValueObservation?
            private var sizeObservation: NSKeyValueObservation?
            private var isAtBottom = true
            private var handledFollowRequest = 0

            override init(frame: CGRect) {
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) is not supported")
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard sizeObservation == nil, let scrollView = resolveScrollView() else { return }
                // Open pinned to the latest entries.
                scrollView.setContentOffset(Self.bottomOffset(of: scrollView), animated: false)
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
                    guard let self else { return }
                    self.isAtBottom = Self.offsetIsAtBottom(view)
                    guard !view.isTracking, !view.isDecelerating, self.isAtBottom else { return }
                    // The collection view reconciles estimated cell heights on its
                    // own schedule and can drift the offset; re-assert the bottom
                    // while the view is supposed to rest there. Setting the offset
                    // re-fires this observer; the guard then passes and the
                    // recursion ends.
                    let bottom = Self.bottomOffset(of: view)
                    if abs(view.contentOffset.y - bottom.y) > 0.5 {
                        view.setContentOffset(bottom, animated: false)
                    }
                }
                sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak scrollView] _, _ in
                    guard let self, let scrollView, self.isAtBottom else { return }
                    scrollView.setContentOffset(Self.bottomOffset(of: scrollView), animated: false)
                }
            }

            func handleFollowRequest(_ request: Int) {
                guard request != handledFollowRequest else { return }
                handledFollowRequest = request
                isAtBottom = true
                if let scrollView = resolveScrollView() {
                    scrollView.setContentOffset(Self.bottomOffset(of: scrollView), animated: false)
                }
            }

            private static func bottomOffset(of scrollView: UIScrollView) -> CGPoint {
                CGPoint(
                    x: 0,
                    y: scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                )
            }

            private static func offsetIsAtBottom(_ scrollView: UIScrollView) -> Bool {
                scrollView.contentOffset.y >= Self.bottomOffset(of: scrollView).y - 1
            }

            /// The follower sits in an overlay next to the list's scroll view:
            /// walk up, then search the ancestor's subtree downwards.
            private func resolveScrollView() -> UIScrollView? {
                func search(_ view: UIView) -> UIScrollView? {
                    if let scrollView = view as? UIScrollView { return scrollView }
                    return view.subviews.lazy.compactMap(search).first
                }
                var anchor = superview
                while let current = anchor {
                    if let scrollView = current as? UIScrollView { return scrollView }
                    if let found = search(current) { return found }
                    anchor = current.superview
                }
                return nil
            }
        }
    }
    #else
    private struct AppKitFollower: NSViewRepresentable {
        let followRequest: Int

        func makeNSView(context: Context) -> FollowerView {
            FollowerView()
        }

        func updateNSView(_ nsView: FollowerView, context: Context) {
            nsView.handleFollowRequest(followRequest)
        }

        fileprivate final class FollowerView: NSView {
            private var offsetObserver: NSObjectProtocol?
            private var frameObserver: NSObjectProtocol?
            private var isAtBottom = true
            private var handledFollowRequest = 0

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) is not supported")
            }

            deinit {
                for observer in [offsetObserver, frameObserver].compactMap({ $0 }) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard frameObserver == nil,
                      let scrollView = resolveScrollView(),
                      let document = scrollView.documentView else { return }
                // Open pinned to the latest entries.
                Self.scrollToBottom(scrollView)
                let clip = scrollView.contentView
                clip.postsBoundsChangedNotifications = true
                offsetObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView else { return }
                    self.isAtBottom = Self.offsetIsAtBottom(scrollView)
                }
                document.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: document, queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView, self.isAtBottom else { return }
                    Self.scrollToBottom(scrollView)
                }
            }

            func handleFollowRequest(_ request: Int) {
                guard request != handledFollowRequest else { return }
                handledFollowRequest = request
                isAtBottom = true
                if let scrollView = resolveScrollView() {
                    Self.scrollToBottom(scrollView)
                }
            }

            private static func scrollToBottom(_ scrollView: NSScrollView) {
                guard let document = scrollView.documentView else { return }
                let clip = scrollView.contentView
                clip.scroll(to: CGPoint(x: 0, y: document.frame.height - clip.bounds.height))
                scrollView.reflectScrolledClipView(clip)
            }

            private static func offsetIsAtBottom(_ scrollView: NSScrollView) -> Bool {
                guard let document = scrollView.documentView else { return true }
                let clip = scrollView.contentView
                return clip.bounds.origin.y >= document.frame.height - clip.bounds.height - 1
            }

            /// The follower sits in an overlay next to the list's scroll view:
            /// walk up, then search each ancestor's subtree downwards (never
            /// the whole window — the sidebar has its own scroll view).
            private func resolveScrollView() -> NSScrollView? {
                func search(_ view: NSView) -> NSScrollView? {
                    if let scrollView = view as? NSScrollView { return scrollView }
                    return view.subviews.lazy.compactMap(search).first
                }
                var anchor = superview
                while let current = anchor {
                    if let scrollView = current as? NSScrollView { return scrollView }
                    if let found = search(current) { return found }
                    anchor = current.superview
                }
                return nil
            }
        }
    }
    #endif
}
