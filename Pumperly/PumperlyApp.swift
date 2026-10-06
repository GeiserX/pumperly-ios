import SwiftUI
import UIKit

@main
struct PumperlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Asks the visible scene to open the settings screen (quick action, `pumperly://settings`).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    static let settingsShortcut = "com.pumperly.app.widget-fuel"

    @Published var settingsRequested = false
}

/// Only here to receive the home screen quick action, which SwiftUI does not expose.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == CarPlaySceneDelegate.sessionRole { return CarPlaySceneDelegate.configuration(for: session) }
        if options.shortcutItem?.type == AppRouter.settingsShortcut {
            AppRouter.shared.settingsRequested = true
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = shortcutItem.type == AppRouter.settingsShortcut
        if handled { AppRouter.shared.settingsRequested = true }
        completionHandler(handled)
    }
}
