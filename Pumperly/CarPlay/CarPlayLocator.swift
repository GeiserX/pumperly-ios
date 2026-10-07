import CoreLocation

/// One location fix for the CarPlay screen, with a timeout so a slow fix never leaves it loading.
/// It never asks for permission: the prompt would appear on the iPhone, not on the car's screen.
@MainActor
final class CarPlayLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CarPlayMapping.LocationOutcome, Never>?

    static func locate(timeout: TimeInterval = 10) async -> CarPlayMapping.LocationOutcome {
        await CarPlayLocator().run(timeout: timeout)
    }

    private func run(timeout: TimeInterval) async -> CarPlayMapping.LocationOutcome {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: return .denied
        }
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

    /// Stations "near me" need a fix from the last 15 minutes; an older cached fix is ignored.
    nonisolated static func recent(_ location: CLLocation?, now: Date = Date()) -> CarPlayMapping.LocationOutcome? {
        guard let location, now.timeIntervalSince(location.timestamp) < 15 * 60 else { return nil }
        return .coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func finish(_ outcome: CarPlayMapping.LocationOutcome) {
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
