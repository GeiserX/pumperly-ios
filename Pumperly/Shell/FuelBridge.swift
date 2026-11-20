import WebKit
import WidgetKit

/// Receives the fuel the user picks in the map's fuel picker. The page posts `{fuel: "<code>"}`
/// to `pumperlyFuel`, and the pick becomes the app's one fuel: the widget, Siri and the watch use it.
///
/// Only a top-level https pumperly.com page may change it, the same check as for the location.
@MainActor
final class FuelBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "pumperlyFuel"

    private let settings: SharedSettings
    private let onChange: (FuelType) -> Void

    init(settings: SharedSettings = SharedSettings(), onChange: @escaping (FuelType) -> Void = FuelBridge.publish) {
        self.settings = settings
        self.onChange = onChange
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        receive(message.body, isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host)
    }

    /// Stores a pick from the page. Split out because a WKScriptMessage cannot be built in a test.
    func receive(_ body: Any, isMainFrame: Bool, scheme: String, host: String) {
        guard NavigationPolicy.mayShareLocation(isMainFrame: isMainFrame, scheme: scheme, host: host),
              let raw = (body as? [String: Any])?["fuel"] as? String,
              let fuel = FuelType(rawValue: raw) else { return }
        // The page already shows this fuel, so the shell must not reload it.
        settings.webFuel = fuel
        guard !settings.hasChosenFuel || settings.fuel != fuel else { return }
        settings.fuel = fuel
        settings.hasChosenFuel = true
        onChange(fuel)
    }

    static func publish(_ fuel: FuelType) {
        WidgetCenter.shared.reloadAllTimelines()
        WatchSync.shared.send(fuel: fuel)
    }
}
