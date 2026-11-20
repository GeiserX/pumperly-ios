import XCTest
@testable import Pumperly

final class ShellModelTests: XCTestCase {
    /// The fuel picked on the first-run sheet opens the map on that fuel.
    func testFirstRunURLOpensTheMapOnTheChosenFuel() throws {
        let url = ShellModel.firstRunURL(fuel: .e5)
        XCTAssertEqual(url.absoluteString, "https://pumperly.com/?fuel=E5")
        XCTAssertTrue(NavigationPolicy.isAllowed(url))
        XCTAssertEqual(ShellModel.firstRunURL(fuel: .b7Premium).absoluteString, "https://pumperly.com/?fuel=B7_PREMIUM")
    }

    /// Behind the error screen the first-run choice becomes what Retry loads.
    @MainActor
    func testFirstRunChoiceIsWhatRetryLoads() {
        let shell = ShellModel(settings: makeSettings(fuel: .b7, webFuel: nil, chosen: false))
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, AppConfig.baseURL)
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.pendingURL?.absoluteString, "https://pumperly.com/?fuel=E5")
        XCTAssertEqual(shell.error, .offline)
    }

    /// A page the app was already on (a restored session, a link) is not replaced by the start page.
    @MainActor
    func testFirstRunChoiceKeepsARestoredPage() throws {
        let page = try XCTUnwrap(URL(string: "https://pumperly.com/es?station=Station-A"))
        let shell = ShellModel(settings: makeSettings(fuel: .b7, webFuel: nil, chosen: false))
        shell.start(restoredURL: page, restoredPendingURL: page, restoredError: .offline)
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.pendingURL, page)
    }

    /// A link that failed before the app was ended stays what Retry loads after the fuel choice.
    @MainActor
    func testFirstRunChoiceKeepsARestoredPendingLink() throws {
        let link = try XCTUnwrap(URL(string: "https://pumperly.com/es?station=Station-A"))
        let shell = ShellModel(settings: makeSettings(fuel: .b7, webFuel: nil, chosen: false))
        shell.start(restoredURL: nil, restoredPendingURL: link, restoredError: .offline)
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.pendingURL, link)
    }

    /// A start page that failed before the app was ended still takes the fuel choice.
    @MainActor
    func testFirstRunChoiceReplacesARestoredFailedStartPage() throws {
        let startPage = try XCTUnwrap(URL(string: "https://pumperly.com/"))
        let shell = ShellModel(settings: makeSettings(fuel: .b7, webFuel: nil, chosen: false))
        shell.start(restoredURL: nil, restoredPendingURL: startPage, restoredError: .offline)
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.pendingURL?.absoluteString, "https://pumperly.com/?fuel=E5")
    }

    // MARK: One fuel for the map, the widget, Siri and the watch

    private func makeSettings(fuel: FuelType, webFuel: FuelType?, chosen: Bool = true) -> SharedSettings {
        let suite = "test.\(UUID().uuidString)"
        let settings = SharedSettings(defaults: UserDefaults(suiteName: suite))
        settings.fuel = fuel
        settings.hasChosenFuel = chosen
        settings.webFuel = webFuel
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return settings
    }

    /// A Shortcut or the widget changed the fuel: the map reloads on it.
    @MainActor
    func testSyncFuelReloadsTheMapOnAFuelChosenElsewhere() {
        let settings = makeSettings(fuel: .b7, webFuel: .b7)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, AppConfig.baseURL)
        settings.fuel = .e10
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
        XCTAssertEqual(settings.webFuel, .e10)
        XCTAssertEqual(shell.error, .offline)
    }

    @MainActor
    func testSyncFuelLeavesThePageWhenTheFuelsMatch() {
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, AppConfig.baseURL)
    }

    /// Before the first choice there is nothing to sync: the first-run sheet asks.
    @MainActor
    func testSyncFuelWaitsForTheFirstChoice() {
        let settings = makeSettings(fuel: .e10, webFuel: nil, chosen: false)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, AppConfig.baseURL)
        XCTAssertNil(settings.webFuel)
    }

    /// Relaunch after a change outside the map (or the first launch after the update): the map
    /// opens on the app's fuel, not on the page it restored.
    @MainActor
    func testStartOpensTheMapOnTheAppFuelWhenThePageHasAnother() throws {
        let page = try XCTUnwrap(URL(string: "https://pumperly.com/es"))
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: page, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
        XCTAssertEqual(settings.webFuel, .e10)
    }

    @MainActor
    func testStartKeepsTheRestoredPageWhenTheFuelsMatch() throws {
        let page = try XCTUnwrap(URL(string: "https://pumperly.com/es"))
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: page, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, page)
    }

    /// A link that failed before the app was ended is still what Retry loads.
    @MainActor
    func testStartKeepsARestoredPendingLinkWhenTheFuelsDiffer() throws {
        let link = try XCTUnwrap(URL(string: "https://pumperly.com/es?station=Station-A"))
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: nil, restoredPendingURL: link, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, link)
    }

    /// The first-run choice is the page's fuel once the map opens on it.
    @MainActor
    func testFirstRunChoiceRecordsThePageFuel() {
        let settings = makeSettings(fuel: .e5, webFuel: nil, chosen: false)
        let shell = ShellModel(settings: settings)
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        settings.hasChosenFuel = true
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(settings.webFuel, .e5)
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e5))
    }

    func testTheSheetIsTitledYourFuel() throws {
        let app = Bundle(for: ShellModel.self)
        let bundle = try XCTUnwrap(app.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        XCTAssertEqual(bundle.localizedString(forKey: "settings.fuel", value: nil, table: nil), "Your fuel")
    }

    func testTheFuelSheetHasEnglishAndSpanishText() throws {
        let app = Bundle(for: ShellModel.self)
        for language in ["en", "es"] {
            let path = try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["settings.title.firstRun", "settings.intro", "settings.fuel", "settings.fuel.footer", "settings.done"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, "\(language) \(key)")
            }
        }
    }
}
