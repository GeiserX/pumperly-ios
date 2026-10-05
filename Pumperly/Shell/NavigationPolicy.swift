import Foundation

/// Where a navigation may go. Mirrors `PumperlyWebViewClient.shouldOverrideUrlLoading` in the
/// Android app: only https pumperly.com loads in the app, everything else leaves it.
enum NavigationDecision: Equatable {
    case loadInApp
    case openExternally
    case cancel
}

enum NavigationPolicy {
    /// Schemes the page may never navigate to, in the app or outside it.
    private static let blockedSchemes: Set<String> = ["javascript", "file", "data", "blob"]

    static func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return AppConfig.allowedHosts.contains(host)
    }

    static func decide(_ url: URL?, isMainFrame: Bool) -> NavigationDecision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if blockedSchemes.contains(scheme) { return .cancel }
        if scheme == "about" { return .loadInApp }
        if isAllowed(url) { return .loadInApp }
        // A frame inside a pumperly.com page (an embed) may load https content in place,
        // but it never sends the user out of the app.
        if !isMainFrame { return scheme == "https" ? .loadInApp : .cancel }
        // Other sites, http, mailto:, tel:, maps: go to Safari or the app that owns the scheme.
        return .openExternally
    }

    /// Only a top-level https pumperly.com page may read the location.
    static func mayShareLocation(isMainFrame: Bool, scheme: String, host: String) -> Bool {
        isMainFrame && scheme.lowercased() == "https" && AppConfig.allowedHosts.contains(host.lowercased())
    }
}
