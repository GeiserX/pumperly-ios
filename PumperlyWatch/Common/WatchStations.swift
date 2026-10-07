import Foundation

/// Loads the cheapest stations near the watch. Used by the watch app and its complications.
enum WatchStations {
    /// A live fix first; when location is allowed but no fix came in time, the last position
    /// the watch saved stands in. Without permission no position is used or sent.
    static func loadEntry(fuel: FuelType, askPermission: Bool, settings: SharedSettings = SharedSettings(),
                          now: Date = Date()) async -> CheapestNearbyEntry {
        #if DEBUG
        // Screenshots and UI checks: sample stations, no location and no network.
        if ProcessInfo.processInfo.environment["PUMPERLY_UITEST_SAMPLE"] == "1" {
            return TimelineMapping.sample(date: now, fuel: fuel)
        }
        #endif
        let latitude: Double
        let longitude: Double
        switch await WatchLocator.locate(askPermission: askPermission) {
        case .coordinate(let lat, let lon):
            // Rounded to about 110 m, for the complications' fallback.
            settings.saveLocation(latitude: lat, longitude: lon, at: now)
            (latitude, longitude) = (lat, lon)
        case .unavailable:
            guard let saved = settings.lastLocation(now: now) else {
                return TimelineMapping.entry(date: now, fuel: fuel, result: nil)
            }
            (latitude, longitude) = (saved.latitude, saved.longitude)
        case .denied:
            return TimelineMapping.entry(date: now, fuel: fuel, result: nil)
        }
        do {
            let stations = try await StationsAPI.fetchNearest(latitude: latitude, longitude: longitude, fuel: fuel)
            return TimelineMapping.entry(date: now, fuel: fuel, result: .success(stations))
        } catch {
            return TimelineMapping.entry(date: now, fuel: fuel, result: .failure(error))
        }
    }
}

/// Strings of the watch app and complications, in the `Watch` table.
enum WatchText {
    static let table = "Watch"

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: table, comment: "")
    }
}

extension FuelType {
    /// SF Symbol for the fuel: a charger for EV, a pump for everything else.
    var watchSymbol: String { self == .ev ? "bolt.car.fill" : "fuelpump.fill" }
}
