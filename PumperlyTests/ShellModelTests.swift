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

    private var link: URL { URL(string: "https://pumperly.com/es?station=ES:Station-A&fuel=LPG")! }

    /// A Shortcut or the widget changed the fuel: the map reloads on it and the watch hears of it.
    /// The page has the fuel only once that load commits.
    @MainActor
    func testSyncFuelReloadsTheMapOnAFuelChosenElsewhere() {
        let settings = makeSettings(fuel: .b7, webFuel: .b7)
        var watch: [FuelType] = []
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .b7))
        settings.fuel = .e10
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
        XCTAssertEqual(shell.requestedFuel, .e10)
        XCTAssertEqual(settings.webFuel, .b7)
        XCTAssertEqual(shell.error, .offline)
        XCTAssertEqual(watch, [.e10])
        // Already waiting for that fuel: nothing more to do.
        shell.syncFuel()
        XCTAssertEqual(watch, [.e10])
    }

    @MainActor
    func testTheSyncLoadSetsThePageFuelWhenItCommits() throws {
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: nil)
        let navigation = try XCTUnwrap(shell.fuelNavigation)
        XCTAssertEqual(shell.requestedFuel, .e10)
        XCTAssertEqual(settings.webFuel, .b7)
        shell.webView(shell.webView, didCommit: navigation)
        XCTAssertEqual(settings.webFuel, .e10)
        XCTAssertNil(shell.requestedFuel)
    }

    @MainActor
    func testSyncFuelLeavesThePageWhenTheFuelsMatch() {
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        var watch: [FuelType] = []
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        let afterStart = shell.pendingURL
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, afterStart)
        XCTAssertEqual(watch, [])
    }

    /// Before the first choice there is nothing to sync: the first-run sheet asks.
    @MainActor
    func testSyncFuelWaitsForTheFirstChoice() {
        let settings = makeSettings(fuel: .e10, webFuel: nil, chosen: false)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, AppConfig.baseURL)
        XCTAssertNil(shell.requestedFuel)
    }

    /// An activation that arrives before the first load must not load a page start() then replaces.
    @MainActor
    func testSyncFuelWaitsForStart() {
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        var watch: [FuelType] = []
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.sceneDidBecomeActive()
        XCTAssertNil(shell.requestedFuel)
        XCTAssertEqual(watch, [])
    }

    /// A widget row or a universal link opened after a Shortcut changed the fuel keeps the page for
    /// this activation; the map syncs at the next one.
    @MainActor
    func testALinkKeepsThePageUntilTheNextActivation() {
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: nil)
        settings.fuel = .lpg
        shell.open(link)
        shell.sceneDidBecomeActive()
        XCTAssertNil(shell.requestedFuel)
        XCTAssertEqual(settings.webFuel, .e10)
        shell.sceneDidEnterBackground()
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.requestedFuel, .lpg)
    }

    /// The activation ran first and the link then replaced its load: the page never had the fuel.
    @MainActor
    func testALinkThatReplacesTheSyncLoadLeavesTheFuelUnsynced() {
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: nil)
        settings.fuel = .lpg
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.requestedFuel, .lpg)
        shell.open(link)
        XCTAssertNil(shell.requestedFuel)
        XCTAssertNil(shell.fuelNavigation)
        XCTAssertEqual(settings.webFuel, .e10)
        shell.sceneDidEnterBackground()
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.requestedFuel, .lpg)
    }

    /// Closing the sheet after a change syncs even when a link holds this activation.
    @MainActor
    func testTheSheetClosingSyncsEvenAfterALink() {
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: nil)
        shell.open(link)
        settings.fuel = .lpg
        shell.syncFuel()
        XCTAssertEqual(shell.requestedFuel, .lpg)
    }

    /// Relaunch after a change outside the map (or the first launch after the update): the map
    /// opens on the app's fuel, not on the page it restored.
    @MainActor
    func testStartOpensTheMapOnTheAppFuelWhenThePageHasAnother() throws {
        let page = try XCTUnwrap(URL(string: "https://pumperly.com/es"))
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        var watch: [FuelType] = []
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.start(restoredURL: page, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
        XCTAssertEqual(shell.requestedFuel, .e10)
        XCTAssertEqual(watch, [.e10])
    }

    /// A restored page with content (a route the page wrote into the address) stays when the fuels match.
    @MainActor
    func testStartKeepsARestoredRoutePageWhenTheFuelsMatch() throws {
        let page = try XCTUnwrap(URL(string: "https://pumperly.com/es?from=40.41,-3.70&to=39.46,-0.37"))
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: page, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, page)
    }

    /// The site's fuel cookie may have expired while the app was closed (WebKit caps script-set
    /// cookies at 7 days), so a launch on the plain map always asks for the app's fuel.
    @MainActor
    func testStartOpensThePlainMapOnTheAppFuelEvenWhenTheFuelsMatch() throws {
        var watch: [FuelType] = []
        for restored in [nil, URL(string: "https://pumperly.com/es"), URL(string: "https://pumperly.com/")] {
            let settings = makeSettings(fuel: .e10, webFuel: .e10)
            let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
            shell.start(restoredURL: restored, restoredPendingURL: nil, restoredError: nil)
            XCTAssertEqual(shell.requestedFuel, .e10, "\(String(describing: restored))")
            XCTAssertNotNil(shell.fuelNavigation)
        }
        let settings = makeSettings(fuel: .e10, webFuel: .e10)
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.start(restoredURL: URL(string: "https://pumperly.com/es"), restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
        // Nothing changed, so the watch is not told again.
        XCTAssertEqual(watch, [])
    }

    /// The site sends / to /<locale>/ and strips the query, so a restored start page is /es.
    func testALocaleRootIsTheStartPage() throws {
        for raw in ["https://pumperly.com", "https://pumperly.com/", "https://pumperly.com/es", "https://pumperly.com/es/"] {
            XCTAssertTrue(ShellModel.isStartPage(try XCTUnwrap(URL(string: raw))), raw)
        }
        for raw in ["https://pumperly.com/es?station=ES:Station-A", "https://pumperly.com/es/privacy",
                    "https://pumperly.com/privacy", "https://example.com/es"] {
            XCTAssertFalse(ShellModel.isStartPage(try XCTUnwrap(URL(string: raw))), raw)
        }
        XCTAssertEqual(ShellModel.startPageFuel(try XCTUnwrap(URL(string: "https://pumperly.com/es?fuel=E5"))), .e5)
        XCTAssertEqual(ShellModel.startPageFuel(try XCTUnwrap(URL(string: "https://pumperly.com/es/?fuel=E5"))), .e5)
    }

    /// A link that failed before the app was ended is still what Retry loads.
    @MainActor
    func testStartKeepsARestoredPendingLinkWhenTheFuelsDiffer() throws {
        let link = try XCTUnwrap(URL(string: "https://pumperly.com/es?station=Station-A"))
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: link, restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, link)
    }

    /// An offline launch saves the shell's own fuel page as what Retry loads. That is not a link: a
    /// fuel set while the app was ended (a Shortcut) replaces it.
    @MainActor
    func testStartReplacesARestoredFuelPageWithTheAppFuel() throws {
        for raw in ["https://pumperly.com/?fuel=E5", "https://pumperly.com/es?fuel=E5"] {
            let saved = try XCTUnwrap(URL(string: raw))
            let settings = makeSettings(fuel: .b7, webFuel: .e5)
            let shell = ShellModel(settings: settings, notifyWatch: { _ in })
            shell.start(restoredURL: nil, restoredPendingURL: saved, restoredError: .offline)
            XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .b7), raw)
            XCTAssertEqual(shell.requestedFuel, .b7, raw)
        }
    }

    /// A Retry on one fuel is replaced when the user goes back to the fuel the page already had.
    @MainActor
    func testSyncFuelReplacesARetryOnAnotherFuelEvenWhenThePageHasTheNewOne() {
        let settings = makeSettings(fuel: .e5, webFuel: .b7)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        XCTAssertEqual(shell.requestedFuel, .e5)
        settings.fuel = .b7
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .b7))
    }

    /// A Retry saved on another fuel is replaced at launch, even when the restored page is a route.
    @MainActor
    func testStartReplacesARetryOnAnotherFuelBehindARestoredRoute() throws {
        let route = try XCTUnwrap(URL(string: "https://pumperly.com/es?from=40.41,-3.70&to=39.46,-0.37"))
        let settings = makeSettings(fuel: .b7, webFuel: .b7)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: route, restoredPendingURL: ShellModel.firstRunURL(fuel: .e5), restoredError: .offline)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .b7))
    }

    /// A failed link restored at launch keeps Retry through the launch activation; the map syncs at
    /// the next one.
    @MainActor
    func testARestoredFailedLinkKeepsRetryThroughTheLaunchActivation() throws {
        let failed = try XCTUnwrap(URL(string: "https://pumperly.com/es?station=Station-A"))
        let settings = makeSettings(fuel: .e10, webFuel: .b7)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: failed, restoredError: .offline)
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.pendingURL, failed)
        shell.sceneDidEnterBackground()
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e10))
    }

    /// The first-run choice loads the map on that fuel; closing the sheet adds nothing.
    @MainActor
    func testFirstRunChoiceIsTheFuelTheMapLoads() {
        let settings = makeSettings(fuel: .e5, webFuel: nil, chosen: false)
        var watch: [FuelType] = []
        let shell = ShellModel(settings: settings, notifyWatch: { watch.append($0) })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        settings.hasChosenFuel = true
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.requestedFuel, .e5)
        shell.syncFuel()
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .e5))
        XCTAssertEqual(watch, [])
    }

    /// The app came back to the foreground while the first-run sheet was up, after one pick; a
    /// second pick on the same sheet still reaches the map.
    @MainActor
    func testASecondFirstRunPickAfterAnActivationReachesTheMap() {
        let settings = makeSettings(fuel: .b7, webFuel: nil, chosen: false)
        let shell = ShellModel(settings: settings, notifyWatch: { _ in })
        shell.start(restoredURL: nil, restoredPendingURL: nil, restoredError: .offline)
        settings.fuel = .e5
        settings.hasChosenFuel = true
        shell.sceneDidBecomeActive()
        XCTAssertEqual(shell.requestedFuel, .e5)
        settings.fuel = .lpg
        shell.applyFirstRunChoice(.lpg)
        XCTAssertEqual(shell.pendingURL, ShellModel.firstRunURL(fuel: .lpg))
    }

    func testStartPageFuelReadsOnlyTheShellsOwnStartPage() throws {
        XCTAssertEqual(ShellModel.startPageFuel(ShellModel.firstRunURL(fuel: .e10)), .e10)
        for raw in ["https://pumperly.com/", "https://pumperly.com/?fuel=XX", "https://example.com/?fuel=E5",
                    "https://pumperly.com/es/privacy?fuel=E5", "https://pumperly.com/?station=ES:Station-A&fuel=E5"] {
            XCTAssertNil(ShellModel.startPageFuel(try XCTUnwrap(URL(string: raw))), raw)
        }
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
