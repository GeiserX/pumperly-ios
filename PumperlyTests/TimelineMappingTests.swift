import XCTest
@testable import Pumperly

final class TimelineMappingTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testPricedFuelShowsCheapestFirst() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-b7"))
        let rows = TimelineMapping.rows(from: stations, fuel: .b7, locale: english)
        // Fixture prices: 4508 1.969, 3217 1.979, 4352 1.975, 4711 1.949, 3218 1.955.
        XCTAssertEqual(rows.map(\.name), ["Shell Madrid", "Repsol Madrid", "Blanca Madrid"])
        XCTAssertEqual(rows.map(\.valueText), ["€1.949", "€1.955", "€1.969"])
        XCTAssertEqual(rows.map(\.distanceText), ["1.5 km", "1.6 km", "1.3 km"])
        XCTAssertEqual(rows.first?.url.absoluteString,
                       "https://pumperly.com/?station=ES:4711&lat=40.43&lng=-3.7085")
    }

    func testEqualPricesFallBackToDistance() {
        let near = station(id: "near", price: 1.5, distance: 0.5)
        let far = station(id: "far", price: 1.5, distance: 3)
        let rows = TimelineMapping.rows(from: [far, near], fuel: .e5, locale: english)
        XCTAssertEqual(rows.map(\.id), ["near", "far"])
    }

    func testStationsWithoutPriceAreDroppedForPricedFuels() {
        let rows = TimelineMapping.rows(from: [station(id: "a", price: nil, distance: 0.1),
                                               station(id: "b", price: 1.6, distance: 2)],
                                        fuel: .b7, locale: english)
        XCTAssertEqual(rows.map(\.id), ["b"])
    }

    func testEVSortsByDistanceAndShowsPower() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-ev")).reversed()
        let rows = TimelineMapping.rows(from: Array(stations), fuel: .ev, locale: english)
        XCTAssertEqual(rows.map(\.valueText), ["360 kW", "50 kW", "7 kW"])
        XCTAssertEqual(rows.first?.name, "Telpark - Plaza del Carmen")
    }

    func testAtMostThreeRows() {
        let stations = (0..<10).map { station(id: "\($0)", price: 1.5 + Double($0) / 100, distance: 1) }
        XCTAssertEqual(TimelineMapping.rows(from: stations, fuel: .b7, locale: english).count, 3)
    }

    func testEntryStates() {
        XCTAssertEqual(TimelineMapping.entry(date: now, fuel: .b7, result: nil).content, .needsLocation)
        XCTAssertEqual(TimelineMapping.entry(date: now, fuel: .b7, result: .success([])).content, .empty)
        XCTAssertEqual(TimelineMapping.entry(date: now, fuel: .b7, result: .failure(URLError(.notConnectedToInternet))).content,
                       .unavailable)
        let ok = TimelineMapping.entry(date: now, fuel: .b7, result: .success([station(id: "a", price: 1.5, distance: 1)]),
                                       locale: english)
        guard case .stations(let rows) = ok.content else { return XCTFail("expected stations") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(ok.fuel, .b7)
        XCTAssertEqual(ok.date, now)
    }

    func testRefreshIsHourlyAndSoonerAfterAFailure() {
        let good = TimelineMapping.entry(date: now, fuel: .b7, result: .success([]))
        XCTAssertEqual(TimelineMapping.nextRefresh(after: good), now.addingTimeInterval(3600))
        let bad = TimelineMapping.entry(date: now, fuel: .b7, result: .failure(URLError(.timedOut)))
        XCTAssertEqual(TimelineMapping.nextRefresh(after: bad), now.addingTimeInterval(900))
    }

    func testWidgetTapTargets() {
        let stations = TimelineMapping.entry(date: now, fuel: .b7, result: .success([station(id: "a", price: 1.5, distance: 1)]))
        XCTAssertEqual(TimelineMapping.tapURL(for: stations).host, "pumperly.com")
        XCTAssertTrue(TimelineMapping.tapURL(for: stations).absoluteString.contains("station=ES:a"))
        let empty = TimelineMapping.entry(date: now, fuel: .b7, result: .success([]))
        XCTAssertEqual(TimelineMapping.tapURL(for: empty), AppConfig.settingsURL)
        let noLocation = TimelineMapping.entry(date: now, fuel: .b7, result: nil)
        XCTAssertEqual(TimelineMapping.tapURL(for: noLocation), AppConfig.baseURL)
        XCTAssertEqual(AppConfig.settingsURL.absoluteString, "pumperly://settings")
    }

    func testSpanishFormatting() {
        let spanish = Locale(identifier: "es_ES")
        let price = TimelineMapping.formatPrice(1.949, currency: "EUR", locale: spanish)
        XCTAssertTrue(price.contains("1,949"), price)
        XCTAssertTrue(price.contains("€"), price)
        XCTAssertEqual(TimelineMapping.formatDistance(1.531, locale: spanish), "1,5 km")
    }

    func testBlankNameFallsBackToBrand() {
        XCTAssertEqual(TimelineMapping.displayName(station(id: "x", price: 1, distance: 1, name: "  ")), "Brand")
    }

    private func station(id: String, price: Double?, distance: Double, name: String = "Station") -> Station {
        Station(id: id, externalId: id, country: "ES", name: name, brand: "Brand", city: "Madrid",
                latitude: 40.4, longitude: -3.7, price: price, currency: "EUR", distanceKm: distance, powerKw: nil)
    }
}
