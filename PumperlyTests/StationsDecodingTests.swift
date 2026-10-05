import XCTest
@testable import Pumperly

final class StationsDecodingTests: XCTestCase {
    func testDecodesLiveFuelResponse() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-b7"))
        XCTAssertEqual(stations.count, 5)
        let first = try XCTUnwrap(stations.first)
        XCTAssertEqual(first.externalId, "4508")
        XCTAssertEqual(first.country, "ES")
        XCTAssertEqual(first.name, "Blanca Madrid")
        XCTAssertEqual(first.brand, "Blanca")
        XCTAssertEqual(first.price, 1.969)
        XCTAssertEqual(first.currency, "EUR")
        XCTAssertEqual(first.distanceKm, 1.308, accuracy: 0.0001)
        // GeoJSON order is [longitude, latitude].
        XCTAssertEqual(first.latitude, 40.405278, accuracy: 0.000001)
        XCTAssertEqual(first.longitude, -3.703139, accuracy: 0.000001)
        XCTAssertNil(first.powerKw)
    }

    func testDecodesLiveEVResponseWithoutPrices() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-ev"))
        XCTAssertEqual(stations.count, 3)
        XCTAssertTrue(stations.allSatisfy { $0.price == nil })
        XCTAssertEqual(stations.first?.powerKw, 360)
    }

    func testErrorBodyThrows() {
        let body = Data(#"{"error":"Invalid parameters"}"#.utf8)
        XCTAssertThrowsError(try StationsAPI.decode(body))
    }

    func testRequestURLRoundsCoordinatesAndNamesTheFuel() throws {
        let url = StationsAPI.nearestURL(latitude: 40.416775, longitude: -3.703790, fuel: .e5)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "pumperly.com")
        XCTAssertEqual(components.path, "/api/stations/nearest")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, ["lat": "40.417", "lon": "-3.704", "radius_km": "10", "fuel": "E5", "limit": "20"])
    }

    func testStationPageUsesTheSiteShareFormat() throws {
        let station = try XCTUnwrap(StationsAPI.decode(Fixture.data("nearest-b7")).first)
        XCTAssertEqual(StationsAPI.pageURL(for: station).absoluteString,
                       "https://pumperly.com/?station=ES:4508&lat=40.40528&lng=-3.70314")
        XCTAssertTrue(NavigationPolicy.isAllowed(StationsAPI.pageURL(for: station)))
    }

    func testFuelCodesMatchTheSite() {
        XCTAssertEqual(FuelType.allCases.map(\.rawValue).sorted(), [
            "ADBLUE", "B10", "B7", "B7_PREMIUM", "B_AGRICULTURAL", "CNG", "E10", "E5", "E5_98",
            "E5_PREMIUM", "E98_E10", "EV", "H2", "HVO", "LNG", "LPG",
        ])
        XCTAssertEqual(FuelType.defaultFuel, .b7)
        XCTAssertTrue(FuelType.Category.allCases.flatMap(\.fuels).count == FuelType.allCases.count)
    }
}
