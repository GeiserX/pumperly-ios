import SwiftUI
import WebKit

/// Owns the web view and its state: progress, the error screen, the URL to retry.
/// Mirrors `MainActivity` in the Android app.
@MainActor
final class ShellModel: NSObject, ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: ShellError?
    @Published private(set) var currentURL: URL?
    /// The URL a failed load wanted, so retry goes back to it.
    @Published private(set) var pendingURL: URL?

    let webView: WKWebView
    private let geolocation = GeolocationBridge()
    private var observations: [NSKeyValueObservation] = []
    private var started = false

    override init() {
        webView = Self.makeWebView(geolocation: geolocation)
        super.init()
        geolocation.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(named: "BrandGreen")
        refresh.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    if NavigationPolicy.isAllowed(webView.url) { self?.currentURL = webView.url }
                }
            },
        ]
    }

    /// The configured web view. Static so the tests can check the user agent on a real instance.
    static func makeWebView(geolocation: GeolocationBridge? = nil) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = UserAgent.applicationName(version: AppConfig.appVersion)
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        if let geolocation {
            configuration.userContentController.addUserScript(GeolocationBridge.userScript)
            configuration.userContentController.add(geolocation, name: GeolocationBridge.handlerName)
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(named: "LaunchBackground")
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    /// First load. A restored session wins over the start page; a restored error is shown again.
    func start(restoredURL: URL?, restoredPendingURL: URL?, restoredError: ShellError?) {
        guard !started else { return }
        started = true
        #if DEBUG
        if let html = ProcessInfo.processInfo.environment["PUMPERLY_UITEST_HTML"] {
            webView.loadHTMLString(html, baseURL: AppConfig.baseURL)
            return
        }
        if let raw = ProcessInfo.processInfo.environment["PUMPERLY_START_URL"], let url = URL(string: raw),
           NavigationPolicy.isAllowed(url) {
            load(url)
            return
        }
        if let raw = ProcessInfo.processInfo.environment["PUMPERLY_UITEST_ERROR"], let forced = ShellError(rawValue: raw) {
            pendingURL = AppConfig.baseURL
            error = forced
            return
        }
        #endif
        let url: URL = restoredURL.flatMap { NavigationPolicy.isAllowed($0) ? $0 : nil } ?? AppConfig.baseURL
        if let restoredError {
            pendingURL = (NavigationPolicy.isAllowed(restoredPendingURL) ? restoredPendingURL : nil) ?? url
            error = restoredError
        } else {
            load(url)
        }
    }

    /// A universal link, a widget tap or any other URL handed to the app.
    func open(_ url: URL) {
        guard NavigationPolicy.isAllowed(url) else { return }
        started = true
        load(url)
    }

    func load(_ url: URL) {
        error = nil
        pendingURL = nil
        webView.load(URLRequest(url: url))
    }

    /// The error screen's button: "Go back" after a certificate error, "Retry" otherwise.
    func performErrorAction() {
        if error == .ssl {
            error = nil
            if webView.canGoBack { webView.goBack() } else { load(AppConfig.baseURL) }
        } else {
            retry()
        }
    }

    func retry() {
        let url = pendingURL ?? webView.url.flatMap { NavigationPolicy.isAllowed($0) ? $0 : nil } ?? AppConfig.baseURL
        load(url)
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        if error != nil { retry() } else { webView.reload() }
        sender.endRefreshing()
    }

    private func fail(_ kind: ShellError, url: URL?) {
        if let url, NavigationPolicy.isAllowed(url) { pendingURL = url }
        error = kind
    }
}

extension ShellModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let url = navigationAction.request.url
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decide(url, isMainFrame: isMainFrame) {
        case .loadInApp:
            return (.allow, preferences)
        case .openExternally:
            if let url { await UIApplication.shared.open(url) }
            return (.cancel, preferences)
        case .cancel:
            return (.cancel, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse,
           http.statusCode >= 400 {
            fail(.page, url: http.url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        geolocation.reset()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        error = nil
        pendingURL = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handle(_ error: Error) {
        guard let kind = ShellError.classify(error) else { return }
        let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        fail(kind, url: failingURL)
    }
}

extension ShellModel: WKUIDelegate {
    /// `target="_blank"` and `window.open`: pumperly.com stays in this view, the rest leaves the app.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        switch NavigationPolicy.decide(url, isMainFrame: true) {
        case .loadInApp: webView.load(URLRequest(url: url))
        case .openExternally: UIApplication.shared.open(url)
        case .cancel: break
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("dialog.ok", comment: ""), style: .default) { _ in
                continuation.resume()
            })
            guard present(alert) else { continuation.resume(); return }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("dialog.cancel", comment: ""), style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("dialog.ok", comment: ""), style: .default) { _ in
                continuation.resume(returning: true)
            })
            guard present(alert) else { continuation.resume(returning: false); return }
        }
    }

    private func present(_ controller: UIViewController) -> Bool {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return false }
        top.present(controller, animated: true)
        return true
    }
}
