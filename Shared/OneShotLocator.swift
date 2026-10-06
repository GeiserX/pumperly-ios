import CoreLocation

/// One when-in-use location fix with a timeout, for App Intents (Siri, Shortcuts, Spotlight).
/// It never asks for permission: Siri may run the intent with no screen to show the prompt,
/// so without permission it answers `.denied` and the app asks when the user opens it.
@MainActor
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    enum Outcome: Equatable {
        case coordinate(latitude: Double, longitude: Double)
        /// Location is not allowed (or not decided yet): use no position at all.
        case denied
        /// Allowed, but no recent fix arrived in time.
        case unavailable
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Outcome, Never>?

    static func locate(timeout: TimeInterval = 10) async -> Outcome {
        await OneShotLocator().run(timeout: timeout)
    }

    private func run(timeout: TimeInterval) async -> Outcome {
        guard Self.isAllowed(manager.authorizationStatus) else { return .denied }
        if let fix = Self.recent(manager.location) { return fix }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(Self.recent(self?.manager.location) ?? .unavailable)
            }
        }
    }

    nonisolated static func isAllowed(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// "Near me" needs a fix from the last 15 minutes; an older cached fix is ignored.
    nonisolated static func recent(_ location: CLLocation?, now: Date = Date()) -> Outcome? {
        guard let location, now.timeIntervalSince(location.timestamp) < 15 * 60 else { return nil }
        return .coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func finish(_ outcome: Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A stale cached fix can arrive first; keep waiting for a recent one until the timeout.
        guard let outcome = Self.recent(locations.last) else { return }
        MainActor.assumeIsolated { finish(outcome) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { finish(denied ? .denied : .unavailable) }
    }
}
