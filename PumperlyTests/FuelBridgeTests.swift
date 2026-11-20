import XCTest
@testable import Pumperly

/// The map's fuel picker posts the user's pick to the shell, which makes it the app's one fuel.
@MainActor
final class FuelBridgeTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testAPickOnTheMapBecomesTheAppFuel() {
        let settings = SharedSettings(defaults: defaults)
        var published: [FuelType] = []
        let bridge = FuelBridge(settings: settings, onChange: { published.append($0) })
        bridge.receive(["fuel": "E5"], isMainFrame: true, scheme: "https", host: "pumperly.com")
        XCTAssertEqual(settings.fuel, .e5)
        XCTAssertTrue(settings.hasChosenFuel)
        XCTAssertEqual(settings.webFuel, .e5)
        XCTAssertEqual(published, [.e5])
    }

    func testOnlyATopLevelHttpsPumperlyPageCanChangeTheFuel() {
        let settings = SharedSettings(defaults: defaults)
        settings.fuel = .b7
        var published = 0
        let bridge = FuelBridge(settings: settings, onChange: { _ in published += 1 })
        bridge.receive(["fuel": "E5"], isMainFrame: true, scheme: "https", host: "example.com")
        bridge.receive(["fuel": "E5"], isMainFrame: false, scheme: "https", host: "pumperly.com")
        bridge.receive(["fuel": "E5"], isMainFrame: true, scheme: "http", host: "pumperly.com")
        bridge.receive(["fuel": "XX"], isMainFrame: true, scheme: "https", host: "pumperly.com")
        bridge.receive("E5", isMainFrame: true, scheme: "https", host: "pumperly.com")
        XCTAssertEqual(settings.fuel, .b7)
        XCTAssertFalse(settings.hasChosenFuel)
        XCTAssertNil(settings.webFuel)
        XCTAssertEqual(published, 0)
    }
}
