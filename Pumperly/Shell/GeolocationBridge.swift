import CoreLocation
import WebKit

/// Answers `navigator.geolocation` from CoreLocation, so the site and the widget share one
/// system permission and the site never asks again on every launch.
///
/// Only a top-level https pumperly.com page gets a position. The injected script denies every
/// other frame in JavaScript, and the native side checks the frame's origin again, because a
/// page script could call the message handler directly.
@MainActor
final class GeolocationBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    static let handlerName = "pumperlyGeolocation"

    weak var webView: WKWebView?
    private let manager: CLLocationManager
    private let settings = SharedSettings()
    private let prefetcher = NearbyPrefetcher()
    /// A pending getCurrentPosition call, with the page's options in milliseconds.
    private struct OneShot {
        var maximumAge: Double
        var timeout: Double?
        var timerArmed = false
    }
    private var oneShotIDs: [Int: OneShot] = [:]
    private var watchIDs: Set<Int> = []
    /// Bumped on every page change, so a timer from the old page never rejects a new page's id.
    private var generation = 0

    static var userScript: WKUserScript {
        let hosts = AppConfig.allowedHosts.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        let source = """
        (function () {
          if (window.__pumperlyGeo || !navigator.geolocation) return;
          var geo = navigator.geolocation;
          var allowed = [\(hosts)];
          var trusted = window.top === window && location.protocol === "https:" &&
            allowed.indexOf(location.hostname.toLowerCase()) !== -1;
          function failure(code, message) {
            return { code: code, message: message, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 };
          }
          if (!trusted) {
            geo.getCurrentPosition = function (ok, fail) {
              if (fail) setTimeout(function () { fail(failure(1, "Location is only shared with pumperly.com")); }, 0);
            };
            geo.watchPosition = function (ok, fail) { geo.getCurrentPosition(ok, fail); return 0; };
            geo.clearWatch = function () {};
            return;
          }
          var callbacks = {}, nextId = 1;
          function post(message) { window.webkit.messageHandlers.\(handlerName).postMessage(message); }
          function finish(id) {
            var cb = callbacks[id]; if (!cb) return null;
            if (cb.once) delete callbacks[id];
            return cb;
          }
          window.__pumperlyGeo = {
            resolve: function (id, position) {
              var cb = finish(id); if (cb) cb.ok(position);
            },
            reject: function (id, code, message) {
              var cb = finish(id); if (cb && cb.fail) cb.fail(failure(code, message));
            }
          };
          function number(value) { return typeof value === "number" && value === value ? value : null; }
          geo.getCurrentPosition = function (ok, fail, options) {
            var id = nextId++; callbacks[id] = { ok: ok, fail: fail, once: true };
            // The native side starts the timeout only once permission is granted, as the web API
            // says, so the time spent on the permission prompt does not count.
            var timeout = number(options && options.timeout);
            timeout = timeout === null || !isFinite(timeout) ? null : Math.max(0, timeout);
            var maximumAge = number(options && options.maximumAge);
            maximumAge = maximumAge === null || maximumAge < 0 ? 0 : Math.min(maximumAge, Number.MAX_SAFE_INTEGER);
            post({ op: "get", id: id, maximumAge: maximumAge, timeout: timeout });
          };
          geo.watchPosition = function (ok, fail) {
            var id = nextId++; callbacks[id] = { ok: ok, fail: fail, once: false };
            post({ op: "watch", id: id });
            return id;
          };
          geo.clearWatch = function (id) {
            if (!callbacks[id]) return;
            delete callbacks[id];
            post({ op: "clear", id: id });
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String,
              let id = (body["id"] as? NSNumber)?.intValue else { return }
        let origin = message.frameInfo.securityOrigin
        guard NavigationPolicy.mayShareLocation(isMainFrame: message.frameInfo.isMainFrame,
                                                scheme: origin.protocol, host: origin.host) else {
            reject([id], code: 1, message: "Location is only shared with pumperly.com")
            return
        }
        switch op {
        case "get":
            oneShotIDs[id] = OneShot(maximumAge: (body["maximumAge"] as? NSNumber)?.doubleValue ?? 0,
                                     timeout: (body["timeout"] as? NSNumber)?.doubleValue)
        case "watch": watchIDs.insert(id)
        case "clear":
            watchIDs.remove(id)
            guard watchIDs.isEmpty else { return }
            manager.stopUpdatingLocation()
            // A pending one-shot was waiting on the watch's updates; it needs its own request now.
            if oneShotIDs.isEmpty { return }
        default: return
        }
        proceed()
    }

    /// Stops location updates when the page goes away (navigation, reload).
    func reset() {
        generation += 1
        oneShotIDs.removeAll()
        watchIDs.removeAll()
        manager.stopUpdatingLocation()
    }

    private func proceed() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            settings.clearLocation()
            StationCache.appGroup?.clear()
            reject(Array(oneShotIDs.keys) + watchIDs, code: 1, message: "Location permission denied")
            oneShotIDs.removeAll()
            watchIDs.removeAll()
        default:
            answerFromCachedFix()
            armTimeouts()
            if watchIDs.isEmpty {
                if !oneShotIDs.isEmpty { manager.requestLocation() }
            } else {
                // requestLocation and startUpdatingLocation cancel each other, and a running watch
                // on a still device sends no new update. Restarting the updates makes CoreLocation
                // send a fresh fix, which answers the one-shot and the watch together.
                if !oneShotIDs.isEmpty { manager.stopUpdatingLocation() }
                manager.startUpdatingLocation()
            }
        }
    }

    /// Starts the page's timeout for each pending one-shot. Called only once permission is
    /// granted, so the time spent on the permission prompt does not count against it.
    private func armTimeouts() {
        let current = generation
        for (id, oneShot) in oneShotIDs where !oneShot.timerArmed {
            oneShotIDs[id]?.timerArmed = true
            guard let timeout = oneShot.timeout else { continue }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(min(timeout, 1e12) * 1_000_000))
                guard let self, self.generation == current, self.oneShotIDs.removeValue(forKey: id) != nil else { return }
                self.reject([id], code: 3, message: "Timeout expired")
            }
        }
    }

    /// A stationary device may never send another update while a watch runs, so a one-shot
    /// whose maximumAge allows the last known fix gets that fix at once.
    private func answerFromCachedFix() {
        guard let cached = manager.location else { return }
        let now = Date()
        let ids = oneShotIDs.filter { Self.cachedFixUsable(location: cached, maximumAgeMs: $0.value.maximumAge, now: now) }.map(\.key)
        guard !ids.isEmpty else { return }
        for id in ids { oneShotIDs[id] = nil }
        resolve(ids, with: cached)
    }

    /// True when a fix is valid and no older than the page's maximumAge (milliseconds).
    nonisolated static func cachedFixUsable(location: CLLocation, maximumAgeMs: Double, now: Date) -> Bool {
        guard maximumAgeMs > 0, location.horizontalAccuracy >= 0 else { return false }
        return now.timeIntervalSince(location.timestamp) * 1000 <= maximumAgeMs
    }

    private func deliver(_ location: CLLocation) {
        let c = location.coordinate
        settings.saveLocation(latitude: c.latitude, longitude: c.longitude)
        prefetcher.positionDelivered(location)
        let ids = Array(oneShotIDs.keys) + watchIDs
        oneShotIDs.removeAll()
        resolve(ids, with: location)
    }

    private func resolve(_ ids: [Int], with location: CLLocation) {
        let c = location.coordinate
        let position: [String: Any] = [
            "coords": [
                "latitude": c.latitude,
                "longitude": c.longitude,
                "accuracy": location.horizontalAccuracy,
                "altitude": Self.valueOrNull(location.altitude, valid: location.verticalAccuracy >= 0),
                "altitudeAccuracy": Self.valueOrNull(location.verticalAccuracy, valid: location.verticalAccuracy >= 0),
                "heading": Self.valueOrNull(location.course, valid: location.course >= 0),
                "speed": Self.valueOrNull(location.speed, valid: location.speed >= 0),
            ],
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: position),
              let json = String(data: data, encoding: .utf8) else { return }
        for id in ids {
            webView?.evaluateJavaScript("window.__pumperlyGeo && window.__pumperlyGeo.resolve(\(id), \(json))")
        }
    }

    /// CoreLocation marks unknown values as negative; the web API wants null.
    private static func valueOrNull(_ value: Double, valid: Bool) -> Any {
        valid ? value : NSNull()
    }

    private func reject<S: Sequence>(_ ids: S, code: Int, message: String) where S.Element == Int {
        let text = message.replacingOccurrences(of: "\"", with: "")
        for id in ids {
            webView?.evaluateJavaScript("window.__pumperlyGeo && window.__pumperlyGeo.reject(\(id), \(code), \"\(text)\")")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // Permission withdrawn: the widget must not keep using a position saved earlier.
            if status == .denied || status == .restricted {
                settings.clearLocation()
                StationCache.appGroup?.clear()
            }
            if !oneShotIDs.isEmpty || !watchIDs.isEmpty { proceed() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { deliver(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            reject(oneShotIDs.keys, code: denied ? 1 : 2, message: "Position unavailable")
            oneShotIDs.removeAll()
        }
    }
}
