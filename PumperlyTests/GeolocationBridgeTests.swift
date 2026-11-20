import CoreLocation
import WebKit
import XCTest
@testable import Pumperly

final class GeolocationBridgeTests: XCTestCase {
    /// Records what the page posts and never answers, like CoreLocation when no new fix arrives.
    private final class SilentHandler: NSObject, WKScriptMessageHandler {
        var bodies: [[String: Any]] = []
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { bodies.append(body) }
        }
    }

    @MainActor
    private func loadPage(_ script: String, handler: SilentHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(GeolocationBridge.userScript)
        configuration.userContentController.add(handler, name: GeolocationBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<script>\(script)</script>", baseURL: URL(string: "https://pumperly.com/"))
        return webView
    }

    @MainActor
    private func waitForResult(_ webView: WKWebView, seconds: TimeInterval) async throws -> Any? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let value = try? await webView.evaluateJavaScript("window.result"), !(value is NSNull) {
                return value
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    /// A one-shot with a timeout must fail with TIMEOUT (3) when no position ever arrives,
    /// so the locate button stops spinning.
    @MainActor
    func testOneShotTimesOutWhenNoFixArrives() async throws {
        let handler = SilentHandler()
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(
              function () { window.result = "position"; },
              function (e) { window.result = e.code; },
              { timeout: 200, maximumAge: 60000 });
            """, handler: handler)
        let result = try await waitForResult(webView, seconds: 10)
        XCTAssertEqual(result as? Int, 3)
        XCTAssertEqual((handler.bodies.first?["maximumAge"] as? NSNumber)?.doubleValue, 60000)
    }

    /// Without a timeout the call keeps waiting, as the web API says.
    @MainActor
    func testOneShotWithoutTimeoutKeepsWaiting() async throws {
        let handler = SilentHandler()
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(
              function () { window.result = "position"; },
              function (e) { window.result = e.code; });
            """, handler: handler)
        let result = try await waitForResult(webView, seconds: 1)
        XCTAssertNil(result)
        // The page ran and asked natively, so the nil above is a real wait, not a blank page.
        XCTAssertEqual(handler.bodies.first?["op"] as? String, "get")
        XCTAssertEqual((handler.bodies.first?["maximumAge"] as? NSNumber)?.doubleValue, 0)
    }

    func testCachedFixWithinMaximumAgeIsUsable() {
        let now = Date()
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), altitude: 0,
                             horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-30))
        XCTAssertTrue(GeolocationBridge.cachedFixUsable(location: fix, maximumAgeMs: 60_000, now: now))
        XCTAssertFalse(GeolocationBridge.cachedFixUsable(location: fix, maximumAgeMs: 10_000, now: now))
        XCTAssertFalse(GeolocationBridge.cachedFixUsable(location: fix, maximumAgeMs: 0, now: now))
    }

    func testCachedFixWithoutValidAccuracyIsNotUsable() {
        let now = Date()
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.4, longitude: -3.7), altitude: 0,
                             horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: now)
        XCTAssertFalse(GeolocationBridge.cachedFixUsable(location: fix, maximumAgeMs: 60_000, now: now))
    }
}
