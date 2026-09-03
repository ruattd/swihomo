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

/// Grouped-form section header: icon + title with tight, fixed spacing — Label's
/// icon-to-text gap renders too wide inside form section headers.
struct SectionHeaderLabel: View {
    let title: Text
    let systemImage: String

    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            // Fixed slot: SF Symbol widths vary, so icons would otherwise push the
            // titles out of vertical alignment across sections.
            Image(systemName: systemImage)
                .frame(width: 24)
            title
        }
        .font(.title3.weight(.semibold))
    }
}

/// Settings-row picker with an explicit menu style: the Form-default picker is
/// list-integrated and swallows press-and-hold, while an explicit `.menu` style renders
/// the native standalone menu control with the compact tap palette and the
/// hold-to-expand option list.
struct SettingsPickerRow<Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    let options: [(value: Selection, label: Text)]

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, options: [(Selection, Text)]) {
        self.title = title
        self._selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { option in
                option.label.tag(option.value)
            }
        }
        .pickerStyle(.menu)
    }
}

extension View {
    /// Tighter than the roomy grouped-Form section defaults. iOS-only: macOS grouped
    /// forms have no section-spacing API and are already compact.
    func compactSectionSpacing() -> some View {
        #if os(iOS)
        self.listSectionSpacing(14)
        #else
        self
        #endif
    }
}

enum SurfaceMetrics {
    static let panelCornerRadius: Double = 20
    // Larger radius suits the roomier touch cards on iOS; macOS pointer rows stay tighter.
    #if os(macOS)
    static let rowCornerRadius: Double = 12
    #else
    static let rowCornerRadius: Double = 16
    #endif

    /// Measured from a real-window GroupBox render on macOS 26: fill = quaternarySystemFill, radius ≈ 10.5.
    /// iOS uses a much rounder box to match its roomier touch surfaces.
    #if os(macOS)
    static let boxCornerRadius: Double = 10.5
    #else
    static let boxCornerRadius: Double = 20
    #endif

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

/// Looks exactly like `.plain`, but adds a press effect on macOS for navigation cards:
/// a dim while held, plus a one-shot shrink-and-bounce that always plays to completion
/// even on the quickest tap (iOS gets that feedback from the interactive glass itself).
/// Pass `contracted` to report the contraction to a container OUTSIDE the label (e.g.
/// a glass card wrapping siblings that must not animate), instead of scaling the label.
struct NavigationCardButtonStyle: ButtonStyle {
    var contracted: Binding<Bool>? = nil

    @State private var localContracted = false
    @State private var pressStart = Date.distantPast
    @State private var pressID = 0

    private var isContracted: Bool { contracted?.wrappedValue ?? localContracted }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
#if os(macOS)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .scaleEffect(contracted == nil && isContracted ? 0.96 : 1)
            // Contract on press-down; bounce back only on release, and never earlier
            // than 120ms in — a quick tap still plays the full shrink, a hold stays
            // shrunk until let go.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    guard !isContracted else { return }
                    pressID += 1
                    pressStart = .now
                    withAnimation(.spring(duration: 0.15)) {
                        setContraction(true)
                    }
                } else {
                    guard isContracted else { return }
                    let id = pressID
                    let remaining = max(0, 0.12 - Date.now.timeIntervalSince(pressStart))
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                        // A newer press supersedes this release.
                        guard id == pressID else { return }
                        withAnimation(.spring(duration: 0.35, bounce: 0.45)) {
                            setContraction(false)
                        }
                    }
                }
            }
#endif
    }

#if os(macOS)
    private func setContraction(_ value: Bool) {
        if let contracted {
            contracted.wrappedValue = value
        } else {
            localContracted = value
        }
    }
#endif
}

extension View {
    /// Freezes `frozen` to `value` while a scroll is in flight and releases it back to nil
    /// on idle, so high-frequency publishes never invalidate list cells mid-scroll.
    /// Requires iOS 18/macOS 15; older systems fall through to live updates.
    @ViewBuilder
    func freezeWhileScrolling<Value: Equatable>(_ value: Value, into frozen: Binding<Value?>) -> some View {
        if #available(iOS 18, macOS 15, *) {
            self.onScrollPhaseChange { _, phase in
                if phase == .idle {
                    frozen.wrappedValue = nil
                } else if frozen.wrappedValue == nil {
                    frozen.wrappedValue = value
                }
            }
        } else {
            self
        }
    }

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
