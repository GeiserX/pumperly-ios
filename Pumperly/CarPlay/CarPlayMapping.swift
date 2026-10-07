import Foundation

/// Pure mapping for the CarPlay screen, kept apart from the CarPlay framework so it can be unit tested.
enum CarPlayMapping {
    /// `CPPointOfInterestTemplate` shows at most 12 points.
    static let maxStations = 12

    /// One station on the car's screen.
    struct Place: Equatable, Identifiable {
        let id: String
        let title: String
        /// Price (or charger power for EV) and distance.
        let subtitle: String
        /// Brand and city.
        let summary: String
        let latitude: Double
        let longitude: Double
    }

    enum State: Equatable {
        case stations([Place])
        /// No position: location is not allowed, or no fix came and none was saved recently.
        case needsLocation
        /// Nothing sells this fuel within the radius.
        case empty
        /// Network or server failure.
        case offline
    }

    /// What the one-shot locator found.
    enum LocationOutcome: Equatable {
        case coordinate(latitude: Double, longitude: Double)
        /// Location is not allowed: use no position at all.
        case denied
        /// Allowed, but no recent fix came in time.
        case unavailable
    }

    /// The buttons of an information screen.
    enum InformationAction: Equatable {
        case retry
        case changeFuel
    }

    /// What a row of the fuel picker does when chosen.
    enum PickerAction: Equatable {
        case select(FuelType)
        case showFuels([FuelType])
    }

    // MARK: Stations

    /// Up to 12 stations in the widget's order (cheapest first, nearest first for EV).
    static func places(from stations: [Station], fuel: FuelType, locale: Locale = .current) -> [Place] {
        let byId = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return TimelineMapping.rows(from: stations, fuel: fuel, locale: locale, limit: maxStations).compactMap { row in
            guard let station = byId[row.id] else { return nil }
            return Place(id: row.id, title: row.name,
                         subtitle: [row.valueText, row.distanceText].compactMap { $0 }.joined(separator: " · "),
                         summary: summary(station), latitude: station.latitude, longitude: station.longitude)
        }
    }

    static func summary(_ station: Station) -> String {
        let brand = station.brand?.trimmingCharacters(in: .whitespaces) ?? ""
        let city = station.city.trimmingCharacters(in: .whitespaces)
        if brand.isEmpty || brand.caseInsensitiveCompare(city) == .orderedSame { return city }
        if city.isEmpty { return brand }
        return "\(brand) · \(city)"
    }

    /// `nil` result means there was no position to ask with.
    static func state(fuel: FuelType, result: Result<[Station], Error>?, locale: Locale = .current) -> State {
        switch result {
        case .none: return .needsLocation
        case .failure: return .offline
        case .success(let stations):
            let places = places(from: stations, fuel: fuel, locale: locale)
            return places.isEmpty ? .empty : .stations(places)
        }
    }

    /// A live fix first; the position the app saved stands in only when location is allowed
    /// but no fix came in time, as in the widget. Without permission no position is used.
    static func position(for outcome: LocationOutcome,
                         saved: (latitude: Double, longitude: Double)?) -> (latitude: Double, longitude: Double)? {
        switch outcome {
        case .coordinate(let latitude, let longitude): return (latitude, longitude)
        case .unavailable: return saved
        case .denied: return nil
        }
    }

    /// Retry everywhere; "Change fuel" too when nothing sells the chosen fuel.
    static func informationActions(for state: State) -> [InformationAction] {
        switch state {
        case .stations: return []
        case .empty: return [.retry, .changeFuel]
        case .needsLocation, .offline: return [.retry]
        }
    }

    // MARK: Fuel picker

    /// Picking a fuel in the car counts as choosing it, as on the phone's settings screen,
    /// so the phone does not ask again on its next launch.
    static func choose(_ fuel: FuelType, in settings: SharedSettings) {
        settings.fuel = fuel
        settings.hasChosenFuel = true
    }

    /// The first level of the picker: one row per category.
    static let categories = FuelType.Category.allCases

    /// A category with a single fuel selects it at once; the others open their fuels.
    static func pickerAction(for category: FuelType.Category) -> PickerAction {
        let fuels = category.fuels
        return fuels.count == 1 ? .select(fuels[0]) : .showFuels(fuels)
    }

    /// The category row shows the chosen fuel when it belongs to that category.
    static func categoryDetail(_ category: FuelType.Category, selected: FuelType) -> String? {
        selected.category == category ? selected.label : nil
    }

    // MARK: Text

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "CarPlay", bundle: .main, comment: "CarPlay")
    }

    /// "Cheapest nearby · Diesel".
    static func title(for fuel: FuelType) -> String {
        String(format: text("carplay.title"), fuel.label)
    }

    /// The search radius as the request sends it, so the text follows `StationsAPI.radiusKm`.
    static var radiusText: String {
        StationsAPI.radiusKm.formatted(.number)
    }

    static func message(for state: State) -> (title: String, message: String)? {
        switch state {
        case .stations: return nil
        case .needsLocation: return (text("carplay.needsLocation.title"), text("carplay.needsLocation.message"))
        case .empty: return (text("carplay.empty.title"), String(format: text("carplay.empty.message"), radiusText))
        case .offline: return (text("carplay.offline.title"), text("carplay.offline.message"))
        }
    }
}
