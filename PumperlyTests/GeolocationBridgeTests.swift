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

    /// Stands in for CoreLocation: a chosen permission state, no fixes, and a log of the calls.
    private final class FakeLocationManager: CLLocationManager {
        var status: CLAuthorizationStatus = .notDetermined
        var calls: [String] = []
        override var authorizationStatus: CLAuthorizationStatus { status }
        override var location: CLLocation? { nil }
        override func requestWhenInUseAuthorization() { calls.append("ask") }
        override func requestLocation() { calls.append("request") }
        override func startUpdatingLocation() { calls.append("start") }
        override func stopUpdatingLocation() { calls.append("stop") }
    }

    @MainActor
    private func loadPage(_ script: String, handler: WKScriptMessageHandler) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(GeolocationBridge.userScript)
        configuration.userContentController.add(handler, name: GeolocationBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<script>\(script)</script>", baseURL: URL(string: "https://pumperly.com/"))
        return webView
    }

    @MainActor
    private func loadPage(_ script: String, bridge: GeolocationBridge) -> WKWebView {
        let webView = loadPage(script, handler: bridge)
        bridge.webView = webView
        return webView
    }

    @MainActor
    private func waitFor(seconds: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
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
        let manager = FakeLocationManager()
        manager.status = .authorizedWhenInUse
        let bridge = GeolocationBridge(manager: manager)
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(
              function () { window.result = "position"; },
              function (e) { window.result = e.code; },
              { timeout: 200, maximumAge: 60000 });
            """, bridge: bridge)
        let result = try await waitForResult(webView, seconds: 10)
        XCTAssertEqual(result as? Int, 3)
    }

    /// The page sends its options to the native side, which owns the timeout.
    @MainActor
    func testOneShotSendsItsOptions() async throws {
        let handler = SilentHandler()
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(function () {}, function () {}, { timeout: 200, maximumAge: 60000 });
            """, handler: handler)
        try await waitFor(seconds: 10) { !handler.bodies.isEmpty }
        XCTAssertEqual((handler.bodies.first?["maximumAge"] as? NSNumber)?.doubleValue, 60000)
        XCTAssertEqual((handler.bodies.first?["timeout"] as? NSNumber)?.doubleValue, 200)
        _ = webView
    }

    /// The time spent on the permission prompt must not count against the page's timeout:
    /// the web API starts the timer only once permission is granted.
    @MainActor
    func testTimeoutStartsOnlyAfterPermissionIsGranted() async throws {
        let manager = FakeLocationManager()
        let bridge = GeolocationBridge(manager: manager)
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(
              function () { window.result = "position"; },
              function (e) { window.result = e.code; },
              { timeout: 200 });
            """, bridge: bridge)
        try await waitFor(seconds: 10) { manager.calls.contains("ask") }
        XCTAssertFalse(manager.calls.contains("request"))
        // The person is still on the prompt, well past the 200 ms timeout.
        let whilePrompting = try await waitForResult(webView, seconds: 1)
        XCTAssertNil(whilePrompting)

        manager.status = .authorizedWhenInUse
        bridge.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.calls.last, "request")
        let afterGrant = try await waitForResult(webView, seconds: 10)
        XCTAssertEqual(afterGrant as? Int, 3)
    }

    /// requestLocation and startUpdatingLocation cancel each other, so with a watch running a
    /// one-shot restarts the updates instead of calling requestLocation.
    @MainActor
    func testOneShotDuringWatchRestartsUpdates() async throws {
        let manager = FakeLocationManager()
        manager.status = .authorizedWhenInUse
        let bridge = GeolocationBridge(manager: manager)
        let webView = loadPage("""
            navigator.geolocation.watchPosition(function () {}, function () {});
            navigator.geolocation.getCurrentPosition(function () {}, function () {});
            """, bridge: bridge)
        try await waitFor(seconds: 10) { manager.calls.count >= 3 }
        XCTAssertEqual(Array(manager.calls.suffix(2)), ["stop", "start"])
        XCTAssertFalse(manager.calls.contains("request"))
        _ = webView
    }

    /// With no watch, a one-shot asks CoreLocation for a single fix.
    @MainActor
    func testOneShotWithoutWatchRequestsOneFix() async throws {
        let manager = FakeLocationManager()
        manager.status = .authorizedWhenInUse
        let bridge = GeolocationBridge(manager: manager)
        let webView = loadPage("""
            navigator.geolocation.getCurrentPosition(function () {}, function () {});
            """, bridge: bridge)
        try await waitFor(seconds: 10) { !manager.calls.isEmpty }
        XCTAssertEqual(manager.calls, ["request"])
        _ = webView
    }

    /// When the last watch ends while a one-shot still waits, the one-shot gets its own request.
    @MainActor
    func testClearingTheWatchKeepsAPendingOneShotAlive() async throws {
        let manager = FakeLocationManager()
        manager.status = .authorizedWhenInUse
        let bridge = GeolocationBridge(manager: manager)
        let webView = loadPage("""
            var id = navigator.geolocation.watchPosition(function () {}, function () {});
            navigator.geolocation.getCurrentPosition(function () {}, function () {});
            navigator.geolocation.clearWatch(id);
            """, bridge: bridge)
        try await waitFor(seconds: 10) { manager.calls.last == "request" }
        XCTAssertEqual(Array(manager.calls.suffix(2)), ["stop", "request"])
        _ = webView
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
        XCTAssertTrue(handler.bodies.first?["timeout"] is NSNull)
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
