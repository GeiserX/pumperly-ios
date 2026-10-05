import Foundation

/// Fuel codes accepted by `GET /api/stations/nearest`.
/// Mirrors `FUEL_TYPE_CODES` in GeiserX/Pumperly `src/types/fuel.ts`.
enum FuelType: String, CaseIterable, Codable, Identifiable, Sendable {
    case b7 = "B7"
    case b7Premium = "B7_PREMIUM"
    case b10 = "B10"
    case bAgricultural = "B_AGRICULTURAL"
    case hvo = "HVO"
    case e5 = "E5"
    case e5Premium = "E5_PREMIUM"
    case e10 = "E10"
    case e5_98 = "E5_98"
    case e98E10 = "E98_E10"
    case lpg = "LPG"
    case cng = "CNG"
    case lng = "LNG"
    case h2 = "H2"
    case ev = "EV"
    case adblue = "ADBLUE"

    /// The site's default fuel (`defaultFuel` in its config).
    static let defaultFuel: FuelType = .b7

    var id: String { rawValue }

    /// EV chargers have no price in the API, so the widget sorts them by distance.
    var hasPrice: Bool { self != .ev }

    var label: String {
        NSLocalizedString("fuel.\(rawValue)", comment: "Fuel type name")
    }

    /// Picker sections, in the order the site lists them.
    enum Category: String, CaseIterable, Identifiable {
        case diesel, gasoline, gas, hydrogen, electric, other
        var id: String { rawValue }
        var label: String { NSLocalizedString("fuel.category.\(rawValue)", comment: "Fuel category") }
        var fuels: [FuelType] { FuelType.allCases.filter { $0.category == self } }
    }

    var category: Category {
        switch self {
        case .b7, .b7Premium, .b10, .bAgricultural, .hvo: return .diesel
        case .e5, .e5Premium, .e10, .e5_98, .e98E10: return .gasoline
        case .lpg, .cng, .lng: return .gas
        case .h2: return .hydrogen
        case .ev: return .electric
        case .adblue: return .other
        }
    }
}
