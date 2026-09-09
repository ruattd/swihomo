import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private enum LogFilter: String, CaseIterable, Identifiable {
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

private enum LogLevelFilter: String, CaseIterable, Identifiable {
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
    @State private var showingClearLogsConfirmation = false

    private var entries: [LogEntry] {
        model.logEntries
            .filter { filter == .all || $0.source.rawValue == filter.rawValue }
            .filter { levelFilter.level == nil || $0.level == levelFilter.level }
            .filter { entry in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [entry.module, entry.message, entry.source.displayName, entry.level.displayName]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        PageNavigationStack {
            List {
                ForEach(entries) { entry in
                    LogEntryRow(entry: entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .contentCard()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }
            .listStyle(.plain)
            // Prepending rows must not move visible content: SwiftUI's implicit
            // insert animation slides existing rows down in content space, and
            // no offset compensation can counter a frame animation.
            .transaction { $0.animation = nil }
            // Keeps the position pixel-exactly when entries prepend: observes
            // the backing scroll view itself (offset + content size) and
            // compensates growth in the same frame — no SwiftUI-side anchoring,
            // whose update timing raced three earlier attempts. Overlay, not
            // background: List drops background representables entirely.
            .overlay(alignment: .top) {
                LogScrollPositionKeeper()
                    .frame(width: 0, height: 0)
            }
            .overlay {
                if entries.isEmpty {
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
                        showingClearLogsConfirmation: $showingClearLogsConfirmation
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
                        showingClearLogsConfirmation: $showingClearLogsConfirmation
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
        }
    }

}

// Toolbar content for the logs page, rendered by the container on macOS (via
// ChromeProvider) and in-page on iOS.
private struct LogsToolbarContent: View {
    @Binding var filter: LogFilter
    @Binding var levelFilter: LogLevelFilter
    @Binding var showingClearLogsConfirmation: Bool

    var body: some View {
        Menu {
            sourceFilterSection
            levelFilterSection
        } label: {
            Label(filter.titleKey, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.medium))
        }

        Menu {
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
                Button {
                    filter = source
                } label: {
                    Label(
                        source.titleKey,
                        systemImage: filter == source ? "checkmark" : "circle"
                    )
                }
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

private struct LogScrollPositionKeeper: View {
    var body: some View {
        #if os(iOS)
        UIKitKeeper()
        #else
        AppKitKeeper()
        #endif
    }

    #if os(iOS)
    private struct UIKitKeeper: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            KeeperView()
        }
        func updateUIView(_ uiView: UIView, context: Context) {}


        private final class KeeperView: UIView {
            private var offsetObservation: NSKeyValueObservation?
            private var sizeObservation: NSKeyValueObservation?
            private var lastContentHeight: CGFloat = 0
            private var isAtTop = true
            /// Where the visible content must rest while rows prepend. The
            /// collection view reconciles estimated cell heights on its own
            /// schedule and moves the offset whenever it likes, so the target
            /// is re-asserted on every offset change until the user drags.
            private var pendingTargetY: CGFloat?

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
                lastContentHeight = scrollView.contentSize.height
                lastContentHeight = scrollView.contentSize.height
                offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
                    guard let self else { return }
                    self.isAtTop = view.contentOffset.y <= -view.adjustedContentInset.top + 1
                    if view.isTracking {
                        // The user owns the offset while dragging.
                        self.pendingTargetY = nil
                    } else if let target = self.pendingTargetY, !view.isDecelerating,
                              abs(view.contentOffset.y - target) > 0.5 {
                        // Setting the offset re-fires this observer; the guard
                        // then passes and the recursion ends.
                        view.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                    }
                }
                sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak scrollView] view, _ in
                    guard let self, let scrollView else { return }
                    let newHeight = view.contentSize.height
                    let growth = newHeight - self.lastContentHeight
                    self.lastContentHeight = newHeight
                    guard growth > 0 else { return }
                    if self.isAtTop {
                        self.pendingTargetY = nil
                        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
                    } else {
                        // Accumulate on the pending target, not the transient
                        // offset — the collection view may not have settled to
                        // the previous target yet.
                        let target = (self.pendingTargetY ?? scrollView.contentOffset.y) + growth
                        self.pendingTargetY = target
                        scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                    }
                }
            }

            /// The keeper sits in an overlay next to the list's scroll view:
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
    private struct AppKitKeeper: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            KeeperView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {}

        private final class KeeperView: NSView {
            private var offsetObserver: NSObjectProtocol?
            private var frameObserver: NSObjectProtocol?
            private var lastContentHeight: CGFloat = 0
            private var isAtTop = true

            override init(frame frameRect: NSRect) {
                super.init(frame: .zero)
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
                lastContentHeight = document.frame.height
                document.postsFrameChangedNotifications = true
                let clip = scrollView.contentView
                clip.postsBoundsChangedNotifications = true
                offsetObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let scrollView else { return }
                    self?.isAtTop = scrollView.contentView.bounds.origin.y <= -scrollView.contentInsets.top + 1
                }
                frameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: document, queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView, let document = scrollView.documentView else { return }
                    let newHeight = document.frame.height
                    let growth = newHeight - self.lastContentHeight
                    self.lastContentHeight = newHeight
                    guard growth > 0 else { return }
                    let clip = scrollView.contentView
                    let targetY = self.isAtTop
                        ? -scrollView.contentInsets.top
                        : clip.bounds.origin.y + growth
                    clip.scroll(to: CGPoint(x: 0, y: targetY))
                    scrollView.reflectScrolledClipView(clip)
                }
            }

            /// The keeper sits in an overlay next to the list's scroll view:
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
