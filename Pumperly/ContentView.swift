import SwiftUI

struct ContentView: View {
    @StateObject private var shell = ShellModel()
    @ObservedObject private var router = AppRouter.shared
    @State private var showingSettings = false

    // Survives the system ending the app in the background, like Android's onSaveInstanceState.
    @SceneStorage("shell.url") private var savedURL: String?
    @SceneStorage("shell.pendingURL") private var savedPendingURL: String?
    @SceneStorage("shell.error") private var savedError: String?

    var body: some View {
        ZStack(alignment: .top) {
            // The top safe area (status bar) shows the site's dark header colour in light and
            // dark mode; the content below runs to the bottom edge.
            Color("SiteHeader").ignoresSafeArea()

            ZStack(alignment: .top) {
                Color("LaunchBackground")

                WebView(webView: shell.webView)
                    .opacity(shell.error == nil ? 1 : 0)

                if let error = shell.error {
                    ErrorView(error: error, action: shell.performErrorAction)
                }

                if shell.isLoading && shell.error == nil {
                    ProgressView(value: shell.progress)
                        .progressViewStyle(.linear)
                        .tint(Color("BrandGreen"))
                        .accessibilityIdentifier("shell.progress")
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            Self.applyTestHooks()
            shell.start(restoredURL: savedURL.flatMap(URL.init(string:)),
                        restoredPendingURL: savedPendingURL.flatMap(URL.init(string:)),
                        restoredError: savedError.flatMap(ShellError.init(rawValue:)))
            // First launch: ask for the widget's fuel once.
            if router.settingsRequested || !SharedSettings().hasChosenFuel {
                router.settingsRequested = false
                showingSettings = true
            }
        }
        .onOpenURL { url in
            if url.scheme == AppConfig.settingsURL.scheme {
                if url.host == AppConfig.settingsURL.host { showingSettings = true }
            } else {
                shell.open(url)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { shell.open(url) }
        }
        .onChange(of: router.settingsRequested) { _, requested in
            guard requested else { return }
            router.settingsRequested = false
            showingSettings = true
        }
        .onChange(of: shell.currentURL) { _, url in savedURL = url?.absoluteString }
        .onChange(of: shell.pendingURL) { _, url in savedPendingURL = url?.absoluteString }
        .onChange(of: shell.error) { _, error in savedError = error?.rawValue }
    }

    /// UI tests start from a known state. Compiled out of Release builds.
    private static func applyTestHooks() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["PUMPERLY_UITEST_RESET"] == "1" { SharedSettings().reset() }
        if environment["PUMPERLY_UITEST_SKIP_INTRO"] == "1" { SharedSettings().hasChosenFuel = true }
        #endif
    }
}
