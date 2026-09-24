import SwiftUI

#if os(macOS)
import AppKit

final class SwihomoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        }
        sender.setActivationPolicy(
            SettingsStore.shared.settings.showsMenuBar && SettingsStore.shared.settings.hidesDockIcon
                ? .accessory
                : .regular
        )
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
#endif

@main
struct SwihomoApp: App {
    @StateObject private var model = AppModel()
    @AppSetting(\.showsMenuBar) private var showsMenuBar
    @AppSetting(\.appLanguage) private var selectedLanguage

    #if os(macOS)
    @NSApplicationDelegateAdaptor(SwihomoAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        let language = selectedLanguage
        #if os(macOS)
        Window("Swihomo", id: "main") {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, language.locale)
                .task {
                    await Task.yield()
                    await model.load()
                }
        }
        .defaultSize(width: 956, height: 680)

        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarContentView()
                .environmentObject(model)
                .environment(\.locale, language.locale)
        } label: {
            MenuBarLabelView(model: model)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, language.locale)
                .task {
                    await model.load()
                }
        }
        #endif
    }
}
