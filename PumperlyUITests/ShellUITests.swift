import XCTest

final class ShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The shell loads a page with no network: the HTML comes from the test bundle and is shown
    /// with pumperly.com as its origin, so the navigation policy, user agent and location bridge
    /// all run as they do on the real site.
    func testShellLoadsBundledFixtureOffline() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "shell-fixture", withExtension: "html"))
        let app = XCUIApplication()
        app.launchEnvironment["PUMPERLY_UITEST_HTML"] = try String(contentsOf: url, encoding: .utf8)
        app.launchEnvironment["PUMPERLY_UITEST_SKIP_INTRO"] = "1"
        app.launch()

        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Pumperly fixture loaded"].waitForExistence(timeout: 20))
        XCTAssertTrue(web.staticTexts["User agent has the app token"].exists)
        XCTAssertTrue(web.staticTexts["Location bridge ready"].exists)
        XCTAssertFalse(app.staticTexts["shell.error.title"].exists)
    }

    func testOfflineScreenOffersRetry() {
        let app = XCUIApplication()
        app.launchEnvironment["PUMPERLY_UITEST_ERROR"] = "offline"
        app.launchEnvironment["PUMPERLY_UITEST_SKIP_INTRO"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["shell.error.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["shell.error.title"].label, "No connection")
        XCTAssertTrue(app.buttons["shell.error.action"].exists)
    }

    /// First launch asks for the fuel once, with nothing picked for the user; the choice sticks across launches.
    func testFirstLaunchAsksForTheWidgetFuelOnce() {
        let app = XCUIApplication()
        app.launchEnvironment["PUMPERLY_UITEST_ERROR"] = "offline"
        app.launchEnvironment["PUMPERLY_UITEST_RESET"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["settings.intro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.staticTexts["Your fuel"].exists)
        // A row near the top: the form is lazy, so rows below the fold do not exist yet.
        let premium = app.buttons["settings.fuel.B7_PREMIUM"]
        XCTAssertTrue(premium.waitForExistence(timeout: 10))
        // Nothing is ticked and nothing can be confirmed until a fuel is tapped.
        let ticked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'settings.fuel.' AND isSelected == true"))
        XCTAssertEqual(ticked.count, 0)
        XCTAssertFalse(app.buttons["settings.done"].isEnabled)
        let bar = app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bar.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertFalse(waitUntilGone(app.staticTexts["settings.intro"], timeout: 3), "swipe-down closed the first-run sheet")
        premium.tap()
        // On a slow CI simulator the first tap can land while the sheet is still animating in.
        if !waitUntilSelected(premium, timeout: 5) { premium.tap() }
        XCTAssertTrue(waitUntilSelected(premium, timeout: 15))
        XCTAssertTrue(app.buttons["settings.done"].isEnabled)
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.staticTexts["shell.error.title"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchEnvironment["PUMPERLY_UITEST_RESET"] = nil
        app.launch()
        XCTAssertTrue(app.staticTexts["shell.error.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["settings.intro"].exists)
        XCTAssertFalse(app.buttons["settings.done"].exists)

        // Opened again later (widget, icon menu), the sheet is about the widget and shows the choice.
        app.open(URL(string: "pumperly://settings")!)
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.staticTexts["Widget fuel"].exists)
        XCTAssertTrue(waitUntilSelected(app.buttons["settings.fuel.B7_PREMIUM"]))
        XCTAssertTrue(app.buttons["settings.done"].isEnabled)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// SwiftUI updates the selected trait a moment after the tap.
    private func waitUntilSelected(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [selected], timeout: timeout) == .completed
    }
}
