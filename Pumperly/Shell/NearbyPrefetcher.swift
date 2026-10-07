import CoreLocation

/// When the page receives a position, also fetches the stations near it for the widget fuel and
/// caches them on the device, so the app and the widget have something to show with no network.
/// Throttled: a new fetch after 15 minutes, or sooner after moving 1 km (but never twice within a
/// minute, so driving with the map open does not send a request per kilometre).
@MainActor
final class NearbyPrefetcher {
    struct Attempt: Equatable {
        let date: Date
        let latitude: Double
        let longitude: Double
    }

    static let interval: TimeInterval = 15 * 60
    static let minimumInterval: TimeInterval = 60
    static let distanceKm = 1.0

    private let settings: SharedSettings
    private let cache: () -> StationCache?
    private var last: Attempt?
    private var inFlight = false

    init(settings: SharedSettings = SharedSettings(), cache: @escaping () -> StationCache? = { StationCache.appGroup }) {
        self.settings = settings
        self.cache = cache
    }

    nonisolated static func shouldFetch(latitude: Double, longitude: Double, now: Date, last: Attempt?) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last.date)
        if elapsed >= interval || elapsed < 0 { return true }
        guard elapsed >= minimumInterval else { return false }
        return StationCache.distanceKm(last.latitude, last.longitude, latitude, longitude) >= distanceKm
    }

    func positionDelivered(_ location: CLLocation, now: Date = Date()) {
        let c = location.coordinate
        guard !inFlight, let cache = cache(),
              Self.shouldFetch(latitude: c.latitude, longitude: c.longitude, now: now, last: last) else { return }
        last = Attempt(date: now, latitude: c.latitude, longitude: c.longitude)
        inFlight = true
        let fuel = settings.fuel
        Task {
            defer { inFlight = false }
            guard let stations = try? await StationsAPI.fetchNearest(latitude: c.latitude, longitude: c.longitude,
                                                                     fuel: fuel) else { return }
            try? cache.save(StationCache.Snapshot(savedAt: now, fuel: fuel, latitude: c.latitude,
                                                  longitude: c.longitude, stations: stations))
        }
    }
}
