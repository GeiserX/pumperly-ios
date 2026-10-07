import SwiftUI

@main
struct PumperlyWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            StationsView(model: model)
        }
    }
}
