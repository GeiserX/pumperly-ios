import Foundation

/// Constants shared by the app and the widget.
enum AppConfig {
    /// The only site the app shows. Navigation outside it opens in Safari.
    static let baseURL = URL(string: "https://pumperly.com")!

    /// Hosts that load inside the app, and the only origins that may read the location.
    static let allowedHosts: Set<String> = ["pumperly.com", "www.pumperly.com"]

    /// Opens the app's settings screen (widget fuel). Used by the widget and the URL scheme.
    static let settingsURL = URL(string: "pumperly://settings")!

    /// App Group shared by the app and the widget extension.
    static let appGroup = "group.com.pumperly.app"

    /// Marketing version from the bundle (MARKETING_VERSION in project.yml).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
