import SwiftUI

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("accessibility.requestFailed")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("accessibility.dismissError")
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: SurfaceMetrics.panelCornerRadius)
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(SurfaceMetrics.panelCornerRadius), style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}
