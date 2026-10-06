import SwiftUI
import XCTest
@testable import Pumperly

final class AccessoryViewsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let spanish = Locale(identifier: "es_ES")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func bundle(_ language: String) throws -> Bundle {
        let app = Bundle(for: ShellModel.self)
        let path = try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    private func station(id: String, name: String, price: Double?, power: Double? = nil,
                         distance: Double) -> Station {
        Station(id: id, externalId: id, country: "ES", name: name, brand: nil, city: "Madrid",
                latitude: 40.4, longitude: -3.7, price: price, currency: "EUR", distanceKm: distance,
                powerKw: power)
    }

    private func entry(_ fuel: FuelType, _ result: Result<[Station], Error>?, locale: Locale) -> CheapestNearbyEntry {
        TimelineMapping.entry(date: now, fuel: fuel, result: result, locale: locale)
    }

    private var pricedStations: [Station] {
        [station(id: "1", name: "Repsol", price: 1.459, distance: 1.1),
         station(id: "2", name: "Cepsa", price: 1.489, distance: 0.3)]
    }

    // MARK: Inline

    func testInlineForPricedFuelInSpanish() throws {
        let es = try bundle("es")
        let line = AccessoryText.inline(entry: entry(.b7, .success(pricedStations), locale: spanish), bundle: es)
        XCTAssertEqual(line, "B7 1,459\u{00A0}€ · Repsol 1,1 km")
    }

    func testInlineForPricedFuelInEnglish() throws {
        let en = try bundle("en")
        let sample = entry(.b7, .success(pricedStations), locale: english)
        XCTAssertEqual(AccessoryText.inline(entry: sample, bundle: en), "B7 €1.459 · Repsol 1.1 km")
        XCTAssertEqual(AccessoryText.inlineCompact(entry: sample, bundle: en), "B7 €1.459")
    }

    func testInlineForEVShowsNearestChargerPower() throws {
        let en = try bundle("en")
        let chargers = [station(id: "far", name: "Iberdrola", price: nil, power: 50, distance: 2.4),
                        station(id: "near", name: "Telpark", price: nil, power: 150, distance: 0.6)]
        let sample = entry(.ev, .success(chargers), locale: english)
        XCTAssertEqual(AccessoryText.inline(entry: sample, bundle: en), "EV 150 kW · Telpark 0.6 km")
        XCTAssertEqual(AccessoryText.inline(entry: sample, bundle: try bundle("es")).prefix(3), "VE ")
    }

    func testInlineForEachMessageState() throws {
        let en = try bundle("en")
        let es = try bundle("es")
        let offline: Result<[Station], Error> = .failure(URLError(.notConnectedToInternet))
        let cases: [(Result<[Station], Error>?, String, String)] = [
            (nil, "B7 · No location", "B7 · Sin ubicación"),
            (.success([]), "B7 · Nothing nearby", "B7 · Nada cerca"),
            (offline, "B7 · Offline", "B7 · Sin conexión"),
        ]
        for (result, english, spanish) in cases {
            let sample = entry(.b7, result, locale: self.english)
            XCTAssertEqual(AccessoryText.inline(entry: sample, bundle: en), english)
            XCTAssertEqual(AccessoryText.inline(entry: sample, bundle: es), spanish)
            XCTAssertEqual(AccessoryText.inlineCompact(entry: sample, bundle: en),
                           String(english.dropFirst("B7 · ".count)))
        }
    }

    func testMessageIsNilWhenThereIsAStation() throws {
        XCTAssertNil(AccessoryText.message(entry: entry(.b7, .success(pricedStations), locale: english),
                                           bundle: try bundle("en")))
    }

    // MARK: Circular and rectangular

    func testCircularValueDropsTheCurrencyAndUnit() {
        XCTAssertEqual(AccessoryText.circularValue(entry: entry(.b7, .success(pricedStations), locale: spanish)), "1,459")
        XCTAssertEqual(AccessoryText.circularValue(entry: entry(.b7, .success(pricedStations), locale: english)), "1.459")
        XCTAssertNil(AccessoryText.circularUnit(entry: entry(.b7, .success(pricedStations), locale: english)))

        let charger = entry(.ev, .success([station(id: "c", name: "Telpark", price: nil, power: 150, distance: 1)]),
                            locale: english)
        XCTAssertEqual(AccessoryText.circularValue(entry: charger), "150")
        XCTAssertEqual(AccessoryText.circularUnit(entry: charger), "kW")
    }

    func testCircularValueIsADashWhenThereIsNone() {
        let noPower = entry(.ev, .success([station(id: "c", name: "Telpark", price: nil, distance: 1)]), locale: english)
        XCTAssertEqual(AccessoryText.circularValue(entry: noPower), "—")
        XCTAssertNil(AccessoryText.circularUnit(entry: noPower))
        XCTAssertEqual(AccessoryText.circularValue(entry: entry(.b7, nil, locale: english)), "—")
        XCTAssertEqual(AccessoryText.circularValue(entry: entry(.b7, .success([]), locale: english)), "—")
    }

    func testRectangularDetail() throws {
        let row = try XCTUnwrap(AccessoryText.cheapest(entry(.b7, .success(pricedStations), locale: spanish)))
        XCTAssertEqual(row.name, "Repsol")
        XCTAssertEqual(AccessoryText.rectangularDetail(row), "1,459\u{00A0}€ · 1,1 km")
    }

    func testMessageSymbolsMatchTheHomeScreenWidget() {
        XCTAssertEqual(AccessoryText.messageSymbol(entry: entry(.b7, nil, locale: english)), "location.slash")
        XCTAssertEqual(AccessoryText.messageSymbol(entry: entry(.b7, .success([]), locale: english)), "fuelpump.slash")
        XCTAssertEqual(AccessoryText.messageSymbol(entry: entry(.b7, .failure(URLError(.timedOut)), locale: english)),
                       "wifi.exclamationmark")
        XCTAssertEqual(AccessoryText.fuelSymbol(.ev), "bolt.car.fill")
        XCTAssertEqual(AccessoryText.fuelSymbol(.e5), "fuelpump.fill")
    }

    @MainActor
    func testRectangularViewRendersTheSampleEntry() {
        let view = AccessoryRectangularView(entry: TimelineMapping.sample(date: now))
            .frame(width: 160, height: 72)
        let image = ImageRenderer(content: view).uiImage
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    // MARK: Strings

    func testAccessoryStringsHaveTheSameKeysInEnglishAndSpanish() throws {
        var keys: [String: Set<String>] = [:]
        for language in ["en", "es"] {
            let path = try XCTUnwrap(try bundle(language).path(forResource: AccessoryText.table, ofType: "strings"),
                                     "\(language) \(AccessoryText.table).strings")
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertTrue(table.values.allSatisfy { !$0.isEmpty }, language)
            keys[language] = Set(table.keys)
        }
        XCTAssertEqual(keys["en"], keys["es"])
        let expected = Set(FuelType.allCases.map { "short.\($0.rawValue)" })
            .union(["message.needsLocation", "message.empty", "message.unavailable"])
        XCTAssertEqual(keys["en"], expected)
    }
}
