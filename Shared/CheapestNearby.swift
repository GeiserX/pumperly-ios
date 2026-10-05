import Foundation
import WidgetKit

/// One line of the widget: a station with its price (or charger power) and the page it opens.
struct StationRow: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let distanceText: String
    /// Price for priced fuels, charger power for EV, nil when the API gave neither.
    let valueText: String?
    let url: URL
}

struct CheapestNearbyEntry: TimelineEntry, Equatable {
    enum Content: Equatable {
        case stations([StationRow])
        /// No location yet: the user has to open the app and allow it.
        case needsLocation
        /// The request worked but nothing sells this fuel within the radius.
        case empty
        /// Network or server failure; the next refresh comes sooner.
        case unavailable
    }

    let date: Date
    let fuel: FuelType
    let content: Content
}

/// Pure mapping from API results to widget entries, kept apart from WidgetKit and CoreLocation
/// so it can be unit tested.
enum TimelineMapping {
    static let maxRows = 3
    static let refreshInterval: TimeInterval = 60 * 60
    static let retryInterval: TimeInterval = 15 * 60

    /// Priced fuels: cheapest first, ties broken by distance, stations without a price dropped.
    /// EV: nearest first, since the API returns no charging price.
    static func rows(from stations: [Station], fuel: FuelType, locale: Locale = .current,
                     limit: Int = maxRows) -> [StationRow] {
        let sorted: [Station]
        if fuel.hasPrice {
            sorted = stations.filter { $0.price != nil }.sorted {
                ($0.price!, $0.distanceKm) < ($1.price!, $1.distanceKm)
            }
        } else {
            sorted = stations.sorted { $0.distanceKm < $1.distanceKm }
        }
        return sorted.prefix(limit).map { station in
            StationRow(
                id: station.id,
                name: displayName(station),
                distanceText: formatDistance(station.distanceKm, locale: locale),
                valueText: fuel.hasPrice
                    ? station.price.map { formatPrice($0, currency: station.currency, locale: locale) }
                    : station.powerKw.map { formatPower($0, locale: locale) },
                url: StationsAPI.pageURL(for: station)
            )
        }
    }

    static func entry(date: Date, fuel: FuelType, result: Result<[Station], Error>?,
                      locale: Locale = .current) -> CheapestNearbyEntry {
        let content: CheapestNearbyEntry.Content
        switch result {
        case .none:
            content = .needsLocation
        case .failure:
            content = .unavailable
        case .success(let stations):
            let rows = rows(from: stations, fuel: fuel, locale: locale)
            content = rows.isEmpty ? .empty : .stations(rows)
        }
        return CheapestNearbyEntry(date: date, fuel: fuel, content: content)
    }

    /// About hourly; sooner after a failure.
    static func nextRefresh(after entry: CheapestNearbyEntry) -> Date {
        entry.date.addingTimeInterval(entry.content == .unavailable ? retryInterval : refreshInterval)
    }

    /// Where a tap on the whole widget goes: the cheapest station, the settings when nothing
    /// sells this fuel nearby (so the user can pick another), the start page otherwise.
    static func tapURL(for entry: CheapestNearbyEntry) -> URL {
        switch entry.content {
        case .stations(let rows): return rows.first?.url ?? AppConfig.baseURL
        case .empty: return AppConfig.settingsURL
        case .needsLocation, .unavailable: return AppConfig.baseURL
        }
    }

    static func displayName(_ station: Station) -> String {
        let name = station.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (station.brand ?? station.city) : name
    }

    static func formatPrice(_ price: Double, currency: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.3f %@", price, currency)
    }

    static func formatDistance(_ km: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: km)) ?? String(km)) km"
    }

    static func formatPower(_ kw: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.maximumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: kw)) ?? String(Int(kw))) kW"
    }

    /// Shown in the widget gallery and while the first timeline loads.
    static func sample(date: Date = Date(), fuel: FuelType = .b7) -> CheapestNearbyEntry {
        let stations = [
            Station(id: "1", externalId: "4508", country: "ES", name: "Blanca Madrid", brand: "Blanca",
                    city: "Madrid", latitude: 40.40528, longitude: -3.70314, price: 1.459,
                    currency: "EUR", distanceKm: 0.4, powerKw: nil),
            Station(id: "2", externalId: "3217", country: "ES", name: "Repsol Madrid", brand: "Repsol",
                    city: "Madrid", latitude: 40.40442, longitude: -3.70539, price: 1.472,
                    currency: "EUR", distanceKm: 1.1, powerKw: nil),
            Station(id: "3", externalId: "1234", country: "ES", name: "Cepsa Atocha", brand: "Cepsa",
                    city: "Madrid", latitude: 40.40701, longitude: -3.69102, price: 1.489,
                    currency: "EUR", distanceKm: 2.3, powerKw: nil),
        ]
        return entry(date: date, fuel: fuel, result: .success(stations))
    }
}
