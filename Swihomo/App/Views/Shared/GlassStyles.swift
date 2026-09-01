/// Shared surfaces follow the HIG layering rule: glass is the functional layer for controls, floating overlays, and Home navigation tiles; `contentCard` is the content layer.

import SwiftUI

enum SurfaceMetrics {
    static let panelCornerRadius: Double = 20
    static let rowCornerRadius: Double = 12

    /// Measured from a real-window GroupBox render on macOS 26: fill = quaternarySystemFill, radius ≈ 10.5.
    static let boxCornerRadius: Double = 10.5

    /// Semantic content-surface fill matching the native GroupBox / grouped-Form box exactly.
    static var contentCardFill: Color {
        #if os(macOS)
        Color(nsColor: .quaternarySystemFill)
        #else
        Color(uiColor: .quaternarySystemFill)
        #endif
    }
}

extension View {
    /// Custom card surface matching native GroupBox metrics. Prefer a real GroupBox for pure
    /// content cards; this exists for selection-state cards needing custom fills/strokes.
    @ViewBuilder
    func contentCard(cornerRadius: Double = SurfaceMetrics.boxCornerRadius) -> some View {
        background(
            SurfaceMetrics.contentCardFill,
            in: RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    /// Reserved for floating overlays above content and Home navigation tiles, never static content cards.
    /// HIG layering keeps glass out of the content layer and avoids glass-on-glass surfaces.
    /// Never place a `liquidGlassButton` inside a glass card: drop the card and let the button float directly,
    /// or use a non-glass button style inside the overlay.
    @ViewBuilder
    func liquidGlassCard(cornerRadius: Double = SurfaceMetrics.panelCornerRadius, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: CGFloat(cornerRadius)))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: CGFloat(cornerRadius)))
            }
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: CGFloat(cornerRadius), style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
