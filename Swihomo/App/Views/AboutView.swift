import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    appIcon
                        .frame(width: 96, height: 96)

                    Text("Swihomo")
                        .font(.title.bold())
                    Text("about.subtitle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    AboutDetailRow(title: "about.version", value: appVersion)
                    Divider()
                    AboutDetailRow(title: "about.build", value: buildNumber)
                    Divider()
                    AboutDetailRow(title: "about.mihomoCore", value: MihomoCoreVersion.version)
                    Divider()
                    AboutDetailRow(title: "about.license", value: "AGPL-3.0")
                }
                .liquidGlassCard(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("about.openSource")
                        .font(.headline)
                    Text("about.openSource.description")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link("about.openSource.viewSwihomo", destination: URL(string: "https://github.com/ruattd/swihomo")!)
                    Link("about.openSource.viewMihomo", destination: URL(string: "https://github.com/MetaCubeX/mihomo")!)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .liquidGlassCard(cornerRadius: 20)
            }
            .padding(20)
            .frame(maxWidth: 560)
        }
        .navigationTitle(Text(LocalizedStringKey("navigation.about")))
    }

    @ViewBuilder
    private var appIcon: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
        #else
        Image(uiImage: UIImage(named: "AboutIcon") ?? UIImage())
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }
}

private struct AboutDetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}
