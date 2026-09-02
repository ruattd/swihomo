/// Shared surfaces follow the HIG layering rule: glass is the functional layer for controls, floating overlays, and Home navigation tiles; `contentCard` is the content layer.

import SwiftUI

/// Settings row: title + control on one line, description on its own line below.
/// Shared by Preferences and Overrides so both settings surfaces stay identical.
struct PreferenceRow<Control: View>: View {
    let title: Text
    let description: Text?
    let descriptionColor: Color
    @ViewBuilder var control: Control

    init(
        title: Text,
        description: Text? = nil,
        descriptionColor: Color = .secondary,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.descriptionColor = descriptionColor
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                title
                Spacer()
                control
            }
            if let description {
                description
                    .font(.caption)
                    .foregroundStyle(descriptionColor)
            }
        }
    }
}

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

extension EdgeInsets {
    /// Standard content insets for a settings row inside a grouped section.
    static var settingsRow: EdgeInsets { EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) }
}

extension View {
    /// Pins the top scroll-edge effect to the soft style (progressive blur). Every page uses
    /// ScrollView/Form containers, so the window no longer latches the style of the last-visited page.
    /// macOS only: iOS must keep the default automatic style — pinning .soft leaves the
    /// navigation bar fully transparent on iOS 27.
    @ViewBuilder
    func uniformTopScrollEdge() -> some View {
#if os(macOS)
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
#else
        self
#endif
    }

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
