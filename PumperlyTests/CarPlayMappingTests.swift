import CarPlay
import XCTest
@testable import Pumperly

final class CarPlayMappingTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testPricedFuelListsCheapestFirstWithPriceDistanceAndBrand() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-b7"))
        let places = CarPlayMapping.places(from: stations, fuel: .b7, locale: english)
        // Fixture prices: 4508 1.969, 3217 1.979, 4352 1.975, 4711 1.949, 3218 1.955.
        XCTAssertEqual(places.map(\.subtitle),
                       ["€1.949 · 1.5 km", "€1.955 · 1.6 km", "€1.969 · 1.3 km", "€1.975 · 1.5 km", "€1.979 · 1.4 km"])
        XCTAssertEqual(places.first?.title, "Shell Madrid")
        XCTAssertEqual(places.first?.summary, "Shell · Madrid")
        XCTAssertEqual(places.first?.id, "3af11023-1dea-4869-8be7-4bbc7d378b2e")
        let shell = try XCTUnwrap(stations.first { $0.externalId == "4711" })
        XCTAssertEqual(places.first?.latitude, shell.latitude)
        XCTAssertEqual(places.first?.longitude, shell.longitude)
    }

    func testEVListsNearestFirstWithPower() throws {
        let stations = try StationsAPI.decode(Fixture.data("nearest-ev")).reversed()
        let places = CarPlayMapping.places(from: Array(stations), fuel: .ev, locale: english)
        XCTAssertEqual(places.map(\.subtitle), ["360 kW · 0.2 km", "50 kW · 0.3 km", "7 kW · 0.3 km"])
        XCTAssertEqual(places.first?.title, "Telpark - Plaza del Carmen")
    }

    func testMissingPowerShowsOnlyTheDistance() {
        let places = CarPlayMapping.places(from: [station(id: "a", price: nil, distance: 2)], fuel: .ev, locale: english)
        XCTAssertEqual(places.map(\.subtitle), ["2.0 km"])
    }

    func testAtMostTwelveStations() {
        let stations = (0..<30).map { station(id: "\($0)", price: 1.5 + Double($0) / 100, distance: 1) }
        let places = CarPlayMapping.places(from: stations, fuel: .b7, locale: english)
        XCTAssertEqual(places.count, 12)
        XCTAssertEqual(places.first?.id, "0")
    }

    func testDuplicateIdsDoNotCrash() {
        let places = CarPlayMapping.places(from: [station(id: "a", price: 1.5, distance: 1),
                                                  station(id: "a", price: 1.6, distance: 2)],
                                           fuel: .b7, locale: english)
        XCTAssertEqual(places.count, 2)
    }

    func testSummaryUsesBrandAndCity() {
        XCTAssertEqual(CarPlayMapping.summary(station(id: "a", brand: "Repsol", city: "Madrid")), "Repsol · Madrid")
        XCTAssertEqual(CarPlayMapping.summary(station(id: "a", brand: nil, city: "Madrid")), "Madrid")
        XCTAssertEqual(CarPlayMapping.summary(station(id: "a", brand: "  ", city: "Madrid")), "Madrid")
        XCTAssertEqual(CarPlayMapping.summary(station(id: "a", brand: "MADRID", city: "Madrid")), "Madrid")
        XCTAssertEqual(CarPlayMapping.summary(station(id: "a", brand: "Repsol", city: "")), "Repsol")
    }

    func testStates() {
        XCTAssertEqual(CarPlayMapping.state(fuel: .b7, result: nil), .needsLocation)
        XCTAssertEqual(CarPlayMapping.state(fuel: .b7, result: .failure(URLError(.notConnectedToInternet))), .offline)
        XCTAssertEqual(CarPlayMapping.state(fuel: .b7, result: .success([])), .empty)
        // Only unpriced stations for a priced fuel: nothing to show.
        XCTAssertEqual(CarPlayMapping.state(fuel: .b7, result: .success([station(id: "a", price: nil, distance: 1)])),
                       .empty)
        guard case .stations(let places) = CarPlayMapping.state(
            fuel: .b7, result: .success([station(id: "a", price: 1.5, distance: 1)]), locale: english)
        else { return XCTFail("expected stations") }
        XCTAssertEqual(places.map(\.id), ["a"])
    }

    func testEveryStateButStationsHasAMessage() {
        XCTAssertNil(CarPlayMapping.message(for: .stations([])))
        for state in [CarPlayMapping.State.needsLocation, .empty, .offline] {
            let message = CarPlayMapping.message(for: state)
            XCTAssertNotNil(message, "\(state)")
            XCTAssertFalse(message?.title.hasPrefix("carplay.") ?? true, "\(state)")
            XCTAssertFalse(message?.message.hasPrefix("carplay.") ?? true, "\(state)")
        }
    }

    func testPositionUsesSavedLocationOnlyWhenAllowedButNoFix() {
        let saved = (latitude: 40.4, longitude: -3.7)
        let live = CarPlayMapping.position(for: .coordinate(latitude: 41, longitude: 2), saved: saved)
        XCTAssertEqual(live?.latitude, 41)
        XCTAssertEqual(live?.longitude, 2)
        XCTAssertEqual(CarPlayMapping.position(for: .unavailable, saved: saved)?.latitude, 40.4)
        XCTAssertNil(CarPlayMapping.position(for: .unavailable, saved: nil))
        XCTAssertNil(CarPlayMapping.position(for: .denied, saved: saved))
    }

    func testPickerCoversEveryFuelOnce() {
        var fuels: [FuelType] = []
        for category in CarPlayMapping.categories {
            switch CarPlayMapping.pickerAction(for: category) {
            case .select(let fuel): fuels.append(fuel)
            case .showFuels(let list):
                XCTAssertGreaterThan(list.count, 1)
                fuels += list
            }
        }
        XCTAssertEqual(fuels.sorted { $0.rawValue < $1.rawValue }, FuelType.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(CarPlayMapping.pickerAction(for: .electric), .select(.ev))
        XCTAssertEqual(CarPlayMapping.pickerAction(for: .diesel), .showFuels(FuelType.Category.diesel.fuels))
    }

    func testCategoryRowShowsTheChosenFuel() {
        XCTAssertEqual(CarPlayMapping.categoryDetail(.diesel, selected: .b7Premium), FuelType.b7Premium.label)
        XCTAssertNil(CarPlayMapping.categoryDetail(.gasoline, selected: .b7Premium))
    }

    func testTitleNamesTheFuel() {
        let title = CarPlayMapping.title(for: .ev)
        XCTAssertTrue(title.contains(FuelType.ev.label), title)
        XCTAssertFalse(title.contains("%@"), title)
    }

    func testStringTablesHaveTheSameKeysInEnglishAndSpanish() throws {
        let app = Bundle(for: ShellModel.self)
        func keys(_ language: String) throws -> Set<String> {
            let path = try XCTUnwrap(app.path(forResource: "CarPlay", ofType: "strings", inDirectory: nil,
                                              forLocalization: language), "\(language) CarPlay.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            return Set(table.keys)
        }
        let english = try keys("en")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english, try keys("es"))
        let used = ["carplay.title", "carplay.loading", "carplay.directions", "carplay.fuel", "carplay.fuel.title",
                    "carplay.selected", "carplay.retry", "carplay.changeFuel", "carplay.needsLocation.title",
                    "carplay.needsLocation.message", "carplay.empty.title", "carplay.empty.message",
                    "carplay.offline.title", "carplay.offline.message"]
        XCTAssertEqual(english, Set(used))
    }

    // MARK: CarPlay objects (built in the simulator, no car connected)

    @MainActor
    func testPointOfInterestCarriesTheMappedText() {
        let place = CarPlayMapping.Place(id: "a", title: "Shell Madrid", subtitle: "€1.949 · 1.5 km",
                                         summary: "Shell · Madrid", latitude: 40.43, longitude: -3.7085)
        let point = CarPlayTemplates.pointOfInterest(place) { _ in }
        XCTAssertEqual(point.title, "Shell Madrid")
        XCTAssertEqual(point.subtitle, "€1.949 · 1.5 km")
        XCTAssertEqual(point.summary, "Shell · Madrid")
        XCTAssertEqual(point.primaryButton?.title, CarPlayMapping.text("carplay.directions"))
        XCTAssertEqual(point.location.name, "Shell Madrid")
        XCTAssertEqual(point.location.placemark.coordinate.latitude, 40.43, accuracy: 1e-9)
    }

    @MainActor
    func testSceneConfigurationUsesTheCarPlayDelegate() {
        XCTAssertEqual(CarPlaySceneDelegate.sessionRole, .carTemplateApplication)
        XCTAssertEqual(CarPlaySceneDelegate.configurationName, "CarPlay")
    }

    private func station(id: String, price: Double? = 1.5, distance: Double = 1, brand: String? = "Brand",
                         city: String = "Madrid") -> Station {
        Station(id: id, externalId: id, country: "ES", name: "Station", brand: brand, city: city,
                latitude: 40.4, longitude: -3.7, price: price, currency: "EUR", distanceKm: distance, powerKw: nil)
    }
}
