import SwiftUI

struct ThemeOptionCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                preview
                    .frame(height: 96)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(theme.titleKey)
                            .font(.headline)
                        Text(theme.subtitleKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(minWidth: 144, maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .liquidGlassCard(cornerRadius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.titleKey) + Text("preferences.appearance.labelSuffix"))
        .accessibilityValue(Text(LocalizedStringKey(isSelected ? "common.selected" : "common.notSelected")))
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(previewBackground)

            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(previewText)
                        .frame(width: 54, height: 7)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(previewCard)
                    .frame(height: 36)
            }
            .padding(12)
        }
    }

    private var previewBackground: AnyShapeStyle {
        switch theme {
        case .light:
            AnyShapeStyle(.white)
        case .dark:
            AnyShapeStyle(Color(red: 0.12, green: 0.13, blue: 0.16))
        case .system:
            AnyShapeStyle(
                LinearGradient(
                    colors: [.white, Color(red: 0.12, green: 0.13, blue: 0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private var previewText: Color {
        theme == .light ? Color.black.opacity(0.7) : .white.opacity(0.8)
    }

    private var previewCard: Color {
        theme == .light ? Color.black.opacity(0.08) : .white.opacity(0.12)
    }
}
