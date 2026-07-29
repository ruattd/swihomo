import SwiftUI

@main
struct SwihomoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        #if os(macOS)
        Window("Swihomo", id: "main") {
            ContentView()
                .environmentObject(model)
                .task {
                    await Task.yield()
                    await model.load()
                }
        }
        .defaultSize(width: 900, height: 680)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabelView(model: model)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await Task.yield()
                    await model.load()
                }
        }
        #endif
    }
}
