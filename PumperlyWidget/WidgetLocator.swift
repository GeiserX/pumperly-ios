import CoreLocation

/// One location fix for a timeline refresh, with a timeout so a slow fix never blanks the widget.
@MainActor
final class WidgetLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    static func currentCoordinate(timeout: TimeInterval = 10) async -> CLLocationCoordinate2D? {
        await WidgetLocator().locate(timeout: timeout)
    }

    private func locate(timeout: TimeInterval) async -> CLLocationCoordinate2D? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        // A recent cached fix is good enough for "stations near me".
        if let cached = manager.location, -cached.timestamp.timeIntervalSinceNow < 15 * 60 {
            return cached.coordinate
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(self?.manager.location?.coordinate)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        MainActor.assumeIsolated { finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
