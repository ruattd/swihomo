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
            UserDefaults.standard.bool(forKey: "showsMenuBar") && UserDefaults.standard.bool(forKey: "hidesDockIcon")
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
    @AppStorage("showsMenuBar") private var showsMenuBar = true
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SwihomoAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        let language = AppLanguage(rawValue: selectedLanguage) ?? .system
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
        .defaultSize(width: 900, height: 680)

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
                    await Task.yield()
                    await model.load()
                }
        }
        #endif
    }
}
