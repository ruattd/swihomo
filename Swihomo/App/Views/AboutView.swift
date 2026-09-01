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
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                appIcon
                    .frame(width: 96, height: 96)

                Text("Swihomo")
                    .font(.title.bold())
                Text("about.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)

            Form {
                Section {
                    AboutDetailRow(title: "about.version", value: appVersion)
                    AboutDetailRow(title: "about.build", value: buildNumber)
                    AboutDetailRow(title: "about.mihomoCore", value: MihomoCoreVersion.version)
                    AboutDetailRow(title: "about.license", value: "AGPL-3.0")
                }

                Section {
                    Text("about.openSource.description")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link("about.openSource.viewSwihomo", destination: URL(string: "https://github.com/ruattd/swihomo")!)
                    Link("about.openSource.viewMihomo", destination: URL(string: "https://github.com/MetaCubeX/mihomo")!)
                } header: {
                    Text("about.openSource")
                }
            }
            .formStyle(.grouped)
            .uniformTopScrollEdge()
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
    }
}
