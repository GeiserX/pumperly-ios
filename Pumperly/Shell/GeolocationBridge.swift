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
    private let manager = CLLocationManager()
    private let settings = SharedSettings()
    private var oneShotIDs: [Int] = []
    private var watchIDs: Set<Int> = []

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
          window.__pumperlyGeo = {
            resolve: function (id, position) {
              var cb = callbacks[id]; if (!cb) return;
              if (cb.once) delete callbacks[id];
              cb.ok(position);
            },
            reject: function (id, code, message) {
              var cb = callbacks[id]; if (!cb) return;
              if (cb.once) delete callbacks[id];
              if (cb.fail) cb.fail(failure(code, message));
            }
          };
          geo.getCurrentPosition = function (ok, fail) {
            var id = nextId++; callbacks[id] = { ok: ok, fail: fail, once: true };
            post({ op: "get", id: id });
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

    override init() {
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
        case "get": oneShotIDs.append(id)
        case "watch": watchIDs.insert(id)
        case "clear":
            watchIDs.remove(id)
            if watchIDs.isEmpty { manager.stopUpdatingLocation() }
            return
        default: return
        }
        proceed()
    }

    /// Stops location updates when the page goes away (navigation, reload).
    func reset() {
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
            reject(oneShotIDs + watchIDs, code: 1, message: "Location permission denied")
            oneShotIDs.removeAll()
            watchIDs.removeAll()
        default:
            if !oneShotIDs.isEmpty { manager.requestLocation() }
            if !watchIDs.isEmpty { manager.startUpdatingLocation() }
        }
    }

    private func deliver(_ location: CLLocation) {
        let c = location.coordinate
        settings.saveLocation(latitude: c.latitude, longitude: c.longitude)
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
        let ids = oneShotIDs + watchIDs
        oneShotIDs.removeAll()
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
            if status == .denied || status == .restricted { settings.clearLocation() }
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
            reject(oneShotIDs, code: denied ? 1 : 2, message: "Position unavailable")
            oneShotIDs.removeAll()
        }
    }
}
