import AppIntents
import CoreLocation
import SwiftUI

/// "Find the cheapest fuel nearby": answers from Siri, Shortcuts and Spotlight without opening the app.
struct CheapestNearbyIntent: AppIntent {
    static let title = LocalizedStringResource("intent.cheapest.title", table: "Intents")
    static let description = IntentDescription(
        LocalizedStringResource("intent.cheapest.description", table: "Intents"))

    /// Empty means the widget's fuel.
    @Parameter(title: LocalizedStringResource("param.fuel", table: "Intents"))
    var fuel: FuelChoice?

    init() {}

    init(fuel: FuelChoice?) {
        self.fuel = fuel
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let settings = SharedSettings()
        let fuel = self.fuel?.fuel ?? settings.fuel
        let answer = await CheapestNearbyLookup.run(
            fuel: fuel, settings: settings,
            locate: { await OneShotLocator.locate() },
            fetch: { latitude, longitude, fuel in
                try await StationsAPI.fetchNearest(latitude: latitude, longitude: longitude, fuel: fuel)
            })
        return .result(dialog: IntentDialog(stringLiteral: CheapestNearbyLookup.dialog(for: answer, fuel: fuel)),
                       view: CheapestNearbySnippet(fuel: fuel, answer: answer))
    }
}

/// What the intent found, before it becomes words.
enum CheapestNearbyAnswer: Equatable {
    /// Ordered and formatted by `TimelineMapping.rows`, the same as the widget.
    case stations([StationRow])
    /// Nothing sells this fuel within the radius.
    case empty
    /// Location is not allowed: the user has to open the app and allow it.
    case needsLocation
    /// Allowed, but no fix came in time and the app saved no recent position.
    case locationUnavailable
    /// Network or server failure.
    case unavailable
}

/// The intent's logic, apart from AppIntents, CoreLocation and the network so it can be unit tested.
enum CheapestNearbyLookup {
    typealias Locate = @MainActor () async -> OneShotLocator.Outcome
    typealias Fetch = (_ latitude: Double, _ longitude: Double, _ fuel: FuelType) async throws -> [Station]

    /// A live fix first; when location is allowed but no fix arrives in time, the last position
    /// the app saved stands in, as in the widget. Without permission no position is used or sent.
    @MainActor
    static func run(fuel: FuelType, settings: SharedSettings, now: Date = Date(), locale: Locale = .current,
                    locate: Locate, fetch: Fetch) async -> CheapestNearbyAnswer {
        let latitude: Double, longitude: Double
        switch await locate() {
        case .coordinate(let lat, let lon):
            (latitude, longitude) = (lat, lon)
        case .unavailable:
            guard let saved = settings.lastLocation(now: now) else { return .locationUnavailable }
            (latitude, longitude) = (saved.latitude, saved.longitude)
        case .denied:
            return .needsLocation
        }
        do {
            let stations = try await fetch(latitude, longitude, fuel)
            let rows = TimelineMapping.rows(from: stations, fuel: fuel, locale: locale)
            return rows.isEmpty ? .empty : .stations(rows)
        } catch {
            return .unavailable
        }
    }

    static func dialog(for answer: CheapestNearbyAnswer, fuel: FuelType, bundle: Bundle = .main) -> String {
        func text(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: "Intents")
        }
        func empty() -> String {
            String(format: text("dialog.empty"), fuel.label, Int(StationsAPI.radiusKm))
        }
        switch answer {
        case .stations(let rows):
            guard let first = rows.first else { return empty() }
            if fuel.hasPrice {
                let key = isSoldByTheLitre(fuel) ? "dialog.priced.litre" : "dialog.priced"
                return String(format: text(key), fuel.label, first.name, first.valueText ?? "", first.distanceText)
            }
            if let power = first.valueText {
                return String(format: text("dialog.ev.power"), first.name, power, first.distanceText)
            }
            return String(format: text("dialog.ev"), first.name, first.distanceText)
        case .empty:
            return empty()
        case .needsLocation:
            return text("dialog.needsLocation")
        case .locationUnavailable:
            return text("dialog.locationUnavailable")
        case .unavailable:
            return text("dialog.unavailable")
        }
    }

    /// The API gives no unit. Liquids are sold by the litre; CNG, LNG and hydrogen usually by
    /// the kilogram, so their dialog names no unit rather than a wrong one.
    static func isSoldByTheLitre(_ fuel: FuelType) -> Bool {
        switch fuel {
        case .cng, .lng, .h2, .ev: return false
        default: return true
        }
    }
}
