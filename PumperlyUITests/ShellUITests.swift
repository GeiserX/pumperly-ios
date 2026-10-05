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

    /// First launch opens the widget fuel screen once; the choice sticks across launches.
    func testFirstLaunchAsksForTheWidgetFuelOnce() {
        let app = XCUIApplication()
        app.launchEnvironment["PUMPERLY_UITEST_ERROR"] = "offline"
        app.launchEnvironment["PUMPERLY_UITEST_RESET"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["settings.intro"].waitForExistence(timeout: 10))
        // A row near the top: the form is lazy, so rows below the fold do not exist yet.
        let premium = app.buttons["settings.fuel.B7_PREMIUM"]
        XCTAssertTrue(premium.waitForExistence(timeout: 10))
        premium.tap()
        // On a slow CI simulator the first tap can land while the sheet is still animating in.
        if !waitUntilSelected(premium, timeout: 5) { premium.tap() }
        XCTAssertTrue(waitUntilSelected(premium, timeout: 15))
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.staticTexts["shell.error.title"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchEnvironment["PUMPERLY_UITEST_RESET"] = nil
        app.launch()
        XCTAssertTrue(app.staticTexts["shell.error.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["settings.intro"].exists)
        XCTAssertFalse(app.buttons["settings.done"].exists)
    }

    /// SwiftUI updates the selected trait a moment after the tap.
    private func waitUntilSelected(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [selected], timeout: timeout) == .completed
    }
}
