#if os(macOS)
import AppKit
import SwiftUI

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case icon
    case speed
    case iconAndSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "Icon Only"
        case .speed: "Speed Only"
        case .iconAndSpeed: "Icon + Speed"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .icon: "preferences.menuBar.display.icon"
        case .speed: "preferences.menuBar.display.speed"
        case .iconAndSpeed: "preferences.menuBar.display.iconAndSpeed"
        }
    }
}

/// Keeps the last rendered label image so unchanged text skips measuring and drawing.
private final class MenuBarLabelImageCache {
    private var key: String?
    private var image: NSImage?

    func image(for key: String, render: () -> NSImage) -> NSImage {
        if self.key == key, let image { return image }
        let image = render()
        self.key = key
        self.image = image
        return image
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var status: MenuBarStatus
    @AppSetting(\.menuBarDisplay) private var menuBarDisplay
    @State private var imageCache = MenuBarLabelImageCache()

    private var display: MenuBarDisplay {
        menuBarDisplay
    }

    var body: some View {
        Image(nsImage: cachedImage(
            upload: byteRate(status.traffic.uploadSpeed),
            download: byteRate(status.traffic.downloadSpeed),
            showsText: display != .icon,
            showsIcon: display != .speed
        ))
    }

    private func cachedImage(
        upload: String,
        download: String,
        showsText: Bool,
        showsIcon: Bool
    ) -> NSImage {
        let key = "\(showsText)|\(showsIcon)|\(upload)|\(download)"
        return imageCache.image(for: key) {
            Self.image(upload: upload, download: download, showsText: showsText, showsIcon: showsIcon)
        }
    }

    private static func image(
        upload: String,
        download: String,
        showsText: Bool,
        showsIcon: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let lines = ["↑ \(upload)", "↓ \(download)"]
        let lineSizes = lines.map { ($0 as NSString).size(withAttributes: textAttributes) }
        let lineHeight = ceil(lineSizes.map(\.height).max() ?? font.capHeight)
        let textWidth = ceil(lineSizes.map(\.width).max() ?? 0)
        let height = lineHeight * CGFloat(lines.count)

        let iconHeight = height - 6
        let iconWidth = ceil(iconHeight * 1.2)
        let spacing: CGFloat = 6
        let size = NSSize(
            width: (showsText ? textWidth : 0) + (showsText && showsIcon ? spacing : 0) + (showsIcon ? iconWidth : 0),
            height: height
        )

        let image = NSImage(size: size, flipped: true) { _ in
            if showsText {
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(
                        at: NSPoint(x: 0, y: CGFloat(index) * lineHeight),
                        withAttributes: textAttributes
                    )
                }
            }

            guard showsIcon else { return true }

            let iconX = showsText ? textWidth + spacing : 0
            let iconY = (height - iconHeight) / 2
            let stemWidth = max(iconHeight * 0.22, 1)
            let diagonalWidth = max(iconHeight * 0.16, 1)
            let leftStemX = iconX + stemWidth / 2
            let rightStemX = iconX + iconWidth - stemWidth / 2
            let leftStemInnerX = iconX + stemWidth
            let rightStemInnerX = iconX + iconWidth - stemWidth
            let top = iconY
            let bottom = iconY + iconHeight
            let centerX = iconX + iconWidth / 2
            let vertexY = (top + bottom) / 2

            // Bury the diagonal caps inside the stems so the upper edges
            // emerge exactly from the stems' top inner corners.
            let dx = centerX - leftStemInnerX
            let dy = vertexY - top
            let length = hypot(dx, dy)
            let sine = dy / length
            let cosine = dx / length
            let leftStart = NSPoint(
                x: leftStemInnerX - sine * diagonalWidth / 2,
                y: top + cosine * diagonalWidth / 2
            )
            let rightStart = NSPoint(
                x: rightStemInnerX + sine * diagonalWidth / 2,
                y: top + cosine * diagonalWidth / 2
            )

            let stems = NSBezierPath()
            stems.move(to: NSPoint(x: leftStemX, y: bottom))
            stems.line(to: NSPoint(x: leftStemX, y: top))
            stems.move(to: NSPoint(x: rightStemX, y: bottom))
            stems.line(to: NSPoint(x: rightStemX, y: top))
            stems.lineWidth = stemWidth
            stems.lineCapStyle = .butt

            let diagonals = NSBezierPath()
            diagonals.move(to: leftStart)
            diagonals.line(to: NSPoint(x: centerX, y: vertexY))
            diagonals.line(to: rightStart)
            diagonals.lineWidth = diagonalWidth
            diagonals.lineCapStyle = .butt
            diagonals.lineJoinStyle = .bevel

            NSColor.black.setStroke()
            stems.stroke()
            diagonals.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var status: MenuBarStatus
    @Environment(\.openWindow) private var openWindow
    @AppSetting(\.menuBarDisplay) private var menuBarDisplay

    private var trafficSummary: String {
        let display = menuBarDisplay
        if display == .icon {
            return "↑ \(byteRate(status.traffic.uploadSpeed)) ↓ \(byteRate(status.traffic.downloadSpeed))"
        }
        return "↑ \(byteCount(status.traffic.uploadTotal)) ↓ \(byteCount(status.traffic.downloadTotal))"
    }

    var body: some View {
        Text(LocalizedStringKey(model.connectionStatusLocalizationKey)) + Text(" · ") + Text(verbatim: trafficSummary)

        Divider()

        Button(LocalizedStringKey(model.isConnected ? "common.disconnect" : "common.connect")) {
            if model.isConnected {
                model.disconnect()
            } else if let profile = model.snapshot.activeProfile {
                Task { await model.connect(profile: profile) }
            }
        }
        .disabled(!model.isConnected && model.snapshot.activeProfile == nil)

        Button("menubar.openApp") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }

        Divider()

        Button("menubar.quitApp") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
#endif
