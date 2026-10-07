import Foundation

/// The last stations fetched near the user, kept on the device so the app and the widget can
/// still show them with no network. One JSON file in the App Group; it never leaves the device.
struct StationCache: Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        let savedAt: Date
        let fuel: FuelType
        /// Rounded to 3 decimals (about 110 m), like every coordinate the app sends.
        let latitude: Double
        let longitude: Double
        let stations: [Station]

        init(savedAt: Date, fuel: FuelType, latitude: Double, longitude: Double, stations: [Station]) {
            self.savedAt = savedAt
            self.fuel = fuel
            self.latitude = StationsAPI.round(latitude)
            self.longitude = StationsAPI.round(longitude)
            self.stations = stations
        }

        /// Fresh enough and for the fuel asked for. A snapshot dated in the future (the clock
        /// moved back) counts as stale rather than showing a time that has not happened yet.
        func isUsable(fuel: FuelType? = nil, maxAge: TimeInterval = StationCache.maxAge, now: Date = Date()) -> Bool {
            let age = now.timeIntervalSince(savedAt)
            return age <= maxAge && age >= -StationCache.clockTolerance && (fuel == nil || fuel == self.fuel)
        }

        /// True when the snapshot was taken close enough to this position for its stations to
        /// still be "nearby".
        func isNear(latitude: Double, longitude: Double, withinKm limit: Double = StationCache.maxDistanceKm) -> Bool {
            StationCache.distanceKm(self.latitude, self.longitude, latitude, longitude) <= limit
        }
    }

    static let fileName = "nearest-cache.json"
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let clockTolerance: TimeInterval = 5 * 60
    /// Half the search radius: further away than this, the cached stations are not nearby any more.
    static let maxDistanceKm = StationsAPI.radiusKm / 2

    let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    /// The cache shared by the app and the widget; nil when the App Group container is missing.
    static var appGroup: StationCache? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)
            .map(StationCache.init(directory:))
    }

    func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// The saved snapshot if it is fresh enough (and for `fuel`, when given). A missing or
    /// unreadable file reads as no snapshot.
    func load(fuel: FuelType? = nil, maxAge: TimeInterval = Self.maxAge, now: Date = Date()) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.isUsable(fuel: fuel, maxAge: maxAge, now: now) else { return nil }
        return snapshot
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Great-circle distance in kilometres.
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
