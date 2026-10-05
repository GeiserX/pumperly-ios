import Foundation

/// The token the site can use to detect the iOS app: `PumperlyiOS/<version>`.
enum UserAgent {
    static let token = "PumperlyiOS"

    /// Appended by WebKit after its default user agent. `Mobile/15E148` is WebKit's own default
    /// application name; keeping it means the site still sees a normal mobile Safari engine.
    static func applicationName(version: String) -> String {
        "Mobile/15E148 \(token)/\(version)"
    }

    /// User agent for the widget's API calls, which run outside WebKit.
    static func widgetUserAgent(version: String) -> String {
        "\(token)/\(version) (Widget)"
    }
}
