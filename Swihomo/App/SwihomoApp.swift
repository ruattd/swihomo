import SwiftUI

@main
struct SwihomoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    await Task.yield()
                    await model.load()
                }
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 680)
        #endif
    }
}
