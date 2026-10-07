import CoreLocation

/// One location fix for the watch app or its complications, with a timeout.
@MainActor
final class WatchLocator: NSObject, CLLocationManagerDelegate {
    enum Outcome: Equatable {
        case coordinate(latitude: Double, longitude: Double)
        /// Location is not allowed (or not asked yet, for the complications): use no position.
        case denied
        /// Allowed, but no recent fix arrived in time: a recent saved position may stand in.
        case unavailable
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Outcome, Never>?
    /// True while the system prompt is up; its answer starts the request.
    private var waitingForPermission = false

    /// - Parameter askPermission: true in the app, which may show the system prompt. The
    ///   complications never prompt.
    static func locate(askPermission: Bool, timeout: TimeInterval = 15) async -> Outcome {
        await WatchLocator().run(askPermission: askPermission, timeout: timeout)
    }

    private func run(askPermission: Bool, timeout: TimeInterval) async -> Outcome {
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            return .denied
        case .notDetermined where !askPermission:
            return .denied
        default:
            break
        }
        if status != .notDetermined, let fix = Self.recent(manager.location) { return fix }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            if status == .notDetermined {
                waitingForPermission = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            // The user may take a while to answer the prompt.
            let wait = status == .notDetermined ? max(timeout, 60) : timeout
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                self?.finish(Self.recent(self?.manager.location) ?? .unavailable)
            }
        }
    }

    /// Stations "near me" need a fix from the last 15 minutes.
    nonisolated static func recent(_ location: CLLocation?, now: Date = Date()) -> Outcome? {
        guard let location, now.timeIntervalSince(location.timestamp) < 15 * 60 else { return nil }
        return .coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
        manager.delegate = nil
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        guard continuation != nil, waitingForPermission else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            waitingForPermission = false
            manager.requestLocation()
        case .denied, .restricted:
            finish(.denied)
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A stale cached fix can arrive first; keep waiting for a recent one until the timeout.
        guard let outcome = Self.recent(locations.last) else { return }
        MainActor.assumeIsolated { finish(outcome) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        // locationUnknown is temporary: Core Location keeps trying until the timeout.
        guard code != .locationUnknown else { return }
        MainActor.assumeIsolated { finish(code == .denied ? .denied : .unavailable) }
    }
}
