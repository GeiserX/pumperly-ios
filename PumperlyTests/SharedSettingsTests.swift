import XCTest
@testable import Pumperly

final class SharedSettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFuelDefaultsToDieselAndPersists() {
        let settings = SharedSettings(defaults: defaults)
        XCTAssertEqual(settings.fuel, .b7)
        settings.fuel = .ev
        XCTAssertEqual(SharedSettings(defaults: defaults).fuel, .ev)
    }

    func testFirstRunFlagAndReset() {
        let settings = SharedSettings(defaults: defaults)
        XCTAssertFalse(settings.hasChosenFuel)
        settings.fuel = .e5
        settings.hasChosenFuel = true
        settings.saveLocation(latitude: 40, longitude: -3)
        settings.reset()
        XCTAssertFalse(settings.hasChosenFuel)
        XCTAssertEqual(settings.fuel, .b7)
        XCTAssertNil(settings.lastLocation())
    }

    func testClearLocationKeepsTheFuel() {
        let settings = SharedSettings(defaults: defaults)
        settings.fuel = .lpg
        settings.saveLocation(latitude: 40, longitude: -3)
        settings.clearLocation()
        XCTAssertNil(settings.lastLocation())
        XCTAssertEqual(settings.fuel, .lpg)
    }

    func testUnknownStoredFuelFallsBackToDefault() {
        defaults.set("KEROSENE", forKey: SharedSettings.fuelKey)
        XCTAssertEqual(SharedSettings(defaults: defaults).fuel, .b7)
    }

    func testSavedLocationIsRoundedAndExpires() throws {
        let settings = SharedSettings(defaults: defaults)
        let saved = Date(timeIntervalSince1970: 1_790_000_000)
        settings.saveLocation(latitude: 40.416775, longitude: -3.703790, at: saved)
        let location = try XCTUnwrap(settings.lastLocation(now: saved.addingTimeInterval(60)))
        XCTAssertEqual(location.latitude, 40.417)
        XCTAssertEqual(location.longitude, -3.704)
        XCTAssertNil(settings.lastLocation(now: saved.addingTimeInterval(SharedSettings.lastLocationMaxAge + 1)))
    }
}
