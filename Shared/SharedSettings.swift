import Foundation

/// Settings the app writes and the widget reads, stored in the App Group.
struct SharedSettings {
    static let fuelKey = "widget.fuel"
    static let fuelChosenKey = "widget.fuelChosen"
    static let latitudeKey = "location.latitude"
    static let longitudeKey = "location.longitude"
    static let locationDateKey = "location.date"

    /// How long a location saved by the app may stand in for a live widget fix.
    static let lastLocationMaxAge: TimeInterval = 7 * 24 * 60 * 60

    let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    var fuel: FuelType {
        get { defaults.string(forKey: Self.fuelKey).flatMap(FuelType.init(rawValue:)) ?? .defaultFuel }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.fuelKey) }
    }

    /// False until the user has confirmed a fuel once; the app opens its settings on first launch.
    var hasChosenFuel: Bool {
        get { defaults.bool(forKey: Self.fuelChosenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.fuelChosenKey) }
    }

    func reset() {
        for key in [Self.fuelKey, Self.fuelChosenKey, Self.latitudeKey, Self.longitudeKey, Self.locationDateKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Saves the last position the app saw, rounded to about 110 m, for the widget's fallback.
    func saveLocation(latitude: Double, longitude: Double, at date: Date = Date()) {
        defaults.set(StationsAPI.round(latitude), forKey: Self.latitudeKey)
        defaults.set(StationsAPI.round(longitude), forKey: Self.longitudeKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.locationDateKey)
    }

    /// The saved position, if it is recent enough.
    func lastLocation(now: Date = Date()) -> (latitude: Double, longitude: Double)? {
        guard let lat = defaults.object(forKey: Self.latitudeKey) as? Double,
              let lon = defaults.object(forKey: Self.longitudeKey) as? Double,
              let stamp = defaults.object(forKey: Self.locationDateKey) as? Double
        else { return nil }
        guard now.timeIntervalSince1970 - stamp <= Self.lastLocationMaxAge else { return nil }
        return (lat, lon)
    }
}
