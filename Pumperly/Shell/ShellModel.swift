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
    private let settings: SharedSettings
    private let fuelBridge: FuelBridge
    private let notifyWatch: (FuelType) -> Void
    /// The shell's own load of a start page on a fuel, until it commits. Only a committed page has
    /// stored that fuel, so only then is it the page's fuel.
    private(set) var fuelNavigation: WKNavigation?
    private var fuelNavigationFuel: FuelType?
    /// Set when a link is handed to the app: it keeps the page until the app next goes to the
    /// background, and the fuel sync waits for the next activation or the sheet closing.
    private var linkOwnsActivation = false
    private var observations: [NSKeyValueObservation] = []
    private var started = false
    /// True while the shell is on the plain start page it chose itself, not a restored page or a link.
    private var onStartPage = false
    #if DEBUG
    /// A UI test hook chose the page; the fuel sync must not replace it with the live site.
    private var testHookOwnsPage = false
    #endif

    init(settings: SharedSettings = SharedSettings(),
         notifyWatch: @escaping (FuelType) -> Void = { WatchSync.shared.send(fuel: $0) }) {
        self.settings = settings
        self.notifyWatch = notifyWatch
        fuelBridge = FuelBridge(settings: settings)
        webView = Self.makeWebView(geolocation: geolocation, fuel: fuelBridge)
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
    static func makeWebView(geolocation: GeolocationBridge? = nil, fuel: FuelBridge? = nil) -> WKWebView {
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
        if let fuel {
            configuration.userContentController.add(fuel, name: FuelBridge.handlerName)
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
        let environment = ProcessInfo.processInfo.environment
        testHookOwnsPage = ["PUMPERLY_UITEST_HTML", "PUMPERLY_START_URL", "PUMPERLY_UITEST_ERROR"]
            .contains { environment[$0] != nil }
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
        let restored = restoredURL.flatMap { NavigationPolicy.isAllowed($0) ? $0 : nil }
        let url = restored ?? AppConfig.baseURL
        let restoredTarget = NavigationPolicy.isAllowed(restoredPendingURL) ? restoredPendingURL : nil
        // The fuel changed outside the map since the page last had it (a Shortcut, the widget, the
        // first launch after an update): open the map on it, unless a failed link is waiting.
        let pendingLink = restoredError != nil && restoredTarget.map { !Self.isStartPage($0) } == true
        if fuelNeedsSync, !pendingLink {
            error = restoredError
            beginFuelSync()
            return
        }
        // A restored pending link is not the start page; a start page that failed is still one.
        onStartPage = restored == nil && (restoredError == nil || restoredTarget.map(Self.isStartPage) ?? true)
        if let restoredError {
            pendingURL = restoredTarget ?? url
            error = restoredError
        } else {
            load(url)
        }
    }

    /// A universal link, a widget tap or any other URL handed to the app.
    func open(_ url: URL) {
        guard NavigationPolicy.isAllowed(url) else { return }
        started = true
        onStartPage = false
        linkOwnsActivation = true
        load(url)
    }

    /// The start page on the app's fuel. The site takes a bare `?fuel=` as the user's choice.
    nonisolated static func firstRunURL(fuel: FuelType) -> URL {
        var components = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "fuel", value: fuel.rawValue)]
        return components.url!
    }

    /// The plain start page, with no path or query. A failed first load saves it as `https://pumperly.com/`.
    nonisolated static func isStartPage(_ url: URL) -> Bool {
        url.host?.lowercased() == AppConfig.baseURL.host && (url.path.isEmpty || url.path == "/") && url.query == nil
    }

    /// The first-run fuel answer: the map reopens on that fuel. A link the app was opened with stays;
    /// behind the error screen the choice becomes what Retry loads.
    func applyFirstRunChoice(_ fuel: FuelType) {
        guard onStartPage else { return }
        onStartPage = false
        let url = Self.firstRunURL(fuel: fuel)
        if error != nil { pendingURL = url } else { load(url) }
    }

    /// Reloads the map on the app's fuel when it changed outside the map: the settings sheet, a
    /// Shortcut or the widget. Behind the error screen it becomes what Retry loads.
    func syncFuel() {
        guard started, fuelNeedsSync else { return }
        beginFuelSync()
    }

    /// The app came to the foreground: a Shortcut or the widget may have changed the fuel. A link
    /// handed to the app since it was last in the background keeps the page.
    func sceneDidBecomeActive() {
        guard !linkOwnsActivation else { return }
        syncFuel()
    }

    func sceneDidEnterBackground() {
        linkOwnsActivation = false
    }

    /// The fuel of the start page the shell is loading or that waits behind the error screen.
    var requestedFuel: FuelType? {
        if fuelNavigation != nil { return fuelNavigationFuel }
        return error != nil ? pendingURL.flatMap(Self.startPageFuel) : nil
    }

    /// True when the user has a fuel that the page neither has nor is loading.
    private var fuelNeedsSync: Bool {
        #if DEBUG
        if testHookOwnsPage { return false }
        #endif
        return settings.hasChosenFuel && settings.fuel != settings.webFuel && settings.fuel != requestedFuel
    }

    /// Opens the map on the app's fuel, or makes it what Retry loads, and tells the watch. The page
    /// is the shell's own start page again, so a first-run choice made after this still replaces it.
    private func beginFuelSync() {
        onStartPage = true
        let fuel = settings.fuel
        notifyWatch(fuel)
        let url = Self.firstRunURL(fuel: fuel)
        if error != nil { pendingURL = url } else { load(url) }
    }

    /// The fuel of a start page made by `firstRunURL`, or nil for any other URL.
    nonisolated static func startPageFuel(_ url: URL) -> FuelType? {
        guard url.host?.lowercased() == AppConfig.baseURL.host, url.path == "/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 1, items[0].name == "fuel" else { return nil }
        return items[0].value.flatMap(FuelType.init(rawValue:))
    }

    func load(_ url: URL) {
        error = nil
        pendingURL = nil
        let navigation = webView.load(URLRequest(url: url))
        fuelNavigationFuel = Self.startPageFuel(url)
        fuelNavigation = fuelNavigationFuel == nil ? nil : navigation
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
        if let fuelNavigation, navigation === fuelNavigation, let fuel = fuelNavigationFuel {
            settings.webFuel = fuel
        }
        fuelNavigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if navigation === fuelNavigation { fuelNavigation = nil }
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if navigation === fuelNavigation { fuelNavigation = nil }
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fuelNavigation = nil
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
