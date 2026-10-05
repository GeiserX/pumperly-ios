import Foundation

/// The three error screens of the Android app: offline (retry), certificate (go back), page (retry).
enum ShellError: String, Codable, CaseIterable {
    case offline
    case ssl
    case page

    /// Maps a WebKit load failure to the screen to show, or nil when it is not a failure
    /// the user should see (a cancelled load, a navigation the policy stopped).
    static func classify(_ error: Error) -> ShellError? {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                return nil
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed, NSURLErrorCallIsActive:
                return .offline
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired, NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return .ssl
            default:
                return .page
            }
        }
        // WebKitErrorDomain 101: URL it cannot show; 102: load stopped by the navigation policy;
        // 204: load handed to a plug-in. All three follow a decision the app made itself.
        if nsError.domain == "WebKitErrorDomain", [101, 102, 204].contains(nsError.code) {
            return nil
        }
        return .page
    }

    var title: String { NSLocalizedString("error.\(rawValue).title", comment: "") }
    var message: String { NSLocalizedString("error.\(rawValue).message", comment: "") }
    var action: String { NSLocalizedString("error.\(rawValue).action", comment: "") }
}
