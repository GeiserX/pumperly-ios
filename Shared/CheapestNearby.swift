import Foundation
import SwiftUI
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
    /// Set when the rows come from the offline cache: the time they were fetched.
    var asOf: Date? = nil
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
        topStations(from: stations, fuel: fuel, limit: limit).map { row(for: $0, fuel: fuel, locale: locale) }
    }

    static func row(for station: Station, fuel: FuelType, locale: Locale = .current) -> StationRow {
        StationRow(
            id: station.id,
            name: displayName(station),
            distanceText: formatDistance(station.distanceKm, locale: locale),
            valueText: fuel.hasPrice
                ? station.price.map { formatPrice($0, currency: station.currency, locale: locale) }
                : station.powerKw.map { formatPower($0, locale: locale) },
            url: StationsAPI.pageURL(for: station, fuel: fuel)
        )
    }

    /// The stations the rows show, in the same order.
    static func topStations(from stations: [Station], fuel: FuelType, limit: Int = maxRows) -> [Station] {
        let sorted: [Station]
        if fuel.hasPrice {
            sorted = stations.filter { $0.price != nil }.sorted {
                ($0.price!, $0.distanceKm) < ($1.price!, $1.distanceKm)
            }
        } else {
            sorted = stations.sorted { $0.distanceKm < $1.distanceKm }
        }
        return Array(sorted.prefix(limit))
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

    /// The last known stations, marked with the time they were fetched. A snapshot with no
    /// rows for its fuel says nothing useful offline, so it reads as unavailable.
    static func entry(date: Date, snapshot: StationCache.Snapshot, locale: Locale = .current) -> CheapestNearbyEntry {
        let rows = rows(from: snapshot.stations, fuel: snapshot.fuel, locale: locale)
        return CheapestNearbyEntry(date: date, fuel: snapshot.fuel, content: rows.isEmpty ? .unavailable : .stations(rows),
                                   asOf: snapshot.savedAt)
    }

    /// Like `entry(date:fuel:result:)`, but a failed fetch falls back to the cached stations
    /// when they are for the same fuel, at most a day old and taken near `position`.
    static func entry(date: Date, fuel: FuelType, result: Result<[Station], Error>?,
                      cached: StationCache.Snapshot?, near position: (latitude: Double, longitude: Double)? = nil,
                      locale: Locale = .current) -> CheapestNearbyEntry {
        if case .failure = result, let cached, cached.isUsable(fuel: fuel, now: date),
           position.map({ cached.isNear(latitude: $0.latitude, longitude: $0.longitude) }) ?? true {
            let fallback = entry(date: date, snapshot: cached, locale: locale)
            if case .stations = fallback.content { return fallback }
        }
        return entry(date: date, fuel: fuel, result: result, locale: locale)
    }

    /// About hourly; sooner after a failure, including one covered by cached rows.
    static func nextRefresh(after entry: CheapestNearbyEntry) -> Date {
        let failed = entry.content == .unavailable || entry.asOf != nil
        return entry.date.addingTimeInterval(failed ? retryInterval : refreshInterval)
    }

    /// When cached rows were fetched: the time for today, weekday and time for an older day.
    static func asOfText(_ date: Date, now: Date = Date(), locale: Locale = .current,
                         timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: now) ? "jmm" : "EEEjmm")
        return formatter.string(from: date)
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
        entry(date: date, fuel: fuel, result: .success(sampleStations))
    }

    static let sampleStations: [Station] = [
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
}

private struct StationsAsOfKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// When the widget's rows come from the offline cache, the time they were fetched.
    var stationsAsOf: Date? {
        get { self[StationsAsOfKey.self] }
        set { self[StationsAsOfKey.self] = newValue }
    }
}

/// A clock and the time the cached rows were fetched; nothing when the rows are live.
struct AsOfLabel: View {
    @Environment(\.stationsAsOf) private var asOf

    var body: some View {
        if let asOf {
            let text = TimelineMapping.asOfText(asOf)
            HStack(spacing: 2) {
                Image(systemName: "clock")
                Text(text)
            }
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: NSLocalizedString("offline.asOf", tableName: "Offline", comment: "Widget: cached rows, with the time"), text))
        }
    }
}
