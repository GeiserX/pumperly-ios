import XCTest

/// Drives the typical user flow against the live site for the App Review screen recording.
/// `scripts/record-demo.sh` runs it with the screen recorder on; a normal test run skips it,
/// because it needs the network and takes about two minutes.
///
/// The pauses are for the viewer: each screen stays up long enough to read.
final class DemoFlowUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var started = Date()
    private var locationAnswered = false
    private var restoreAnimationWaits: (() -> Void)?

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PUMPERLY_DEMO"] == "1",
                          "Demo recording only: run scripts/record-demo.sh")
        continueAfterFailure = false
    }

    override func tearDown() {
        restoreAnimationWaits?()
        super.tearDown()
    }

    func testDemoFlow() throws {
        started = Date()
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        // Without this, XCUITest's own handler answers a system alert with "Don't Allow".
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'While Using'")).firstMatch
            guard allow.exists else { return false }
            self.step("location allowed by the interruption monitor")
            allow.tap()
            self.locationAnswered = true
            return true
        }
        app.launch()

        chooseFuelOnFirstLaunch()
        showMapWithPrices()
        searchRoute(to: "Toledo")
        openStationFromList()
        openWidgetFuelSettings()
        addWidgetToHomeScreen()
        step("done")
    }

    // MARK: - Steps

    private func chooseFuelOnFirstLaunch() {
        XCTAssertTrue(app.staticTexts["settings.intro"].waitForExistence(timeout: 30), "first-launch fuel screen")
        // record-demo.sh starts the screen recorder on this line, so the video opens on the app.
        step("first-launch fuel screen")
        pause(2)
        // The site asks for location as soon as it loads, behind the fuel screen.
        allowLocation(timeout: 20)
        let petrol = app.buttons["settings.fuel.E5"]
        XCTAssertTrue(petrol.waitForExistence(timeout: 10))
        petrol.tap()
        pause(2)
        if !closeFuelScreen() {
            // The fuel is already saved, so a relaunch goes straight to the map.
            step("fuel screen stuck: relaunching the app")
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 15), "map after the relaunch")
        }
        allowLocation(timeout: 3)
    }

    /// Answers the system location alert with "Allow While Using App", so the widget gets
    /// location too ("Allow Once" would leave the widget without it).
    private func allowLocation(timeout: TimeInterval) {
        guard !locationAnswered else { return }
        if answerAlert(button: NSPredicate(format: "label CONTAINS[c] 'While Using'"), timeout: timeout, name: "location") {
            locationAnswered = true
        }
    }

    /// Taps a button on a system alert if one shows up within `timeout`. A tap on a system alert
    /// does not always land, so each attempt is checked and the next one tries another way.
    @discardableResult
    private func answerAlert(button predicate: NSPredicate, timeout: TimeInterval, name: String) -> Bool {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return false }
        step("\(name) alert")
        pause(2)
        let button = alert.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), springboardDump("\(name) alert button"))
        let attempts: [(String, () -> Void)] = [
            ("tap", { button.tap() }),
            ("coordinate tap", { button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }),
            ("press", { button.press(forDuration: 0.2) }),
        ]
        for (how, attempt) in attempts where alert.exists {
            attempt()
            if alert.waitForNonExistence(timeout: 3) {
                step("\(name) alert answered by \(how)")
                return true
            }
            step("\(name) alert still up after \(how), frame \(button.frame)")
        }
        // The last attempt can land after its wait ran out.
        if !alert.exists { return true }
        XCTFail(springboardDump("the \(name) alert did not close"))
        return false
    }

    private func showMapWithPrices() {
        step("map with prices")
        XCTAssertTrue(destinationField.waitForExistence(timeout: 40), "site loaded")
        pause(1)
        // The site asks for location once the page has loaded, which on a busy machine is late.
        allowLocation(timeout: 30)
        pause(1)
        useEuros()
        pause(2)
    }

    /// The site guesses the currency from the browser language, and WebKit reports English as
    /// en-US or en-GB whatever the region, so the prices start in dollars or pounds. The stations
    /// are in Spain: pick euros in the site's menu, as a visitor from abroad would.
    private func useEuros() {
        let currency = web.descendants(matching: .any)
            .matching(NSPredicate(format: "value MATCHES %@", "^\\S+ [A-Z]{3}$")).firstMatch
        let menu = web.otherElements["navigation"].buttons.allElementsBoundByIndex.last
        guard let menu, menu.exists else { return step("currency: site menu not found") }
        step("currency: euros")
        menu.tap()
        guard currency.waitForExistence(timeout: 10) else { return step("currency: picker not found") }
        if (currency.value as? String)?.hasSuffix("EUR") == true {
            menu.tap()
            return
        }
        pause(1)
        // Like the search box, the select does not always open on the first tap.
        let euro = app.descendants(matching: .any).matching(NSPredicate(format: "label == '€ EUR'")).firstMatch
        for _ in 0..<3 where !euro.exists {
            currency.tap()
            _ = euro.waitForExistence(timeout: 5)
        }
        guard euro.exists else { return step("currency: euro option not found\n\(app.debugDescription)") }
        pause(1)
        euro.tap()
    }

    private func searchRoute(to city: String) {
        step("route search")
        let field = destinationField
        focus(field)
        // A fresh simulator explains swipe typing the first time the keyboard opens.
        let keyboardTip = app.buttons["Continue"]
        if keyboardTip.waitForExistence(timeout: 2) {
            keyboardTip.tap()
            pause(1)
        }
        for character in city {
            field.typeText(String(character))
            usleep(250_000)
        }
        let suggestion = web.staticTexts[city].firstMatch
        if suggestion.waitForExistence(timeout: 15) {
            pause(2)
            suggestion.tap()
        }
        // The suggestions react to mousedown, which a synthesized tap does not always produce.
        // Return in the search box picks the first suggestion, as on a hardware keyboard.
        if !suggestion.waitForNonExistence(timeout: 2) {
            step("suggestion tap did not land: pressing Return")
            field.typeText("\n")
        }
        step("waiting for route")
        XCTAssertTrue(routeSummary.waitForExistence(timeout: 60), webDump("route summary"))
        // The search box keeps focus after the pick; the keyboard would hide the station list.
        let keyboardDone = app.toolbars.buttons["Done"].firstMatch
        if keyboardDone.exists { keyboardDone.tap() } else if app.keyboards.firstMatch.exists { app.typeText("\n") }
        pause(3)
    }

    private func openStationFromList() {
        step("station list")
        let resize = web.buttons.matching(NSPredicate(format: "label IN %@",
                                                      ["Resize panel", "Cambiar tamaño del panel"])).firstMatch
        // A station row: brand, name, price (1.459 €), km along the route.
        let station = web.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*[0-9][.,][0-9]{3} .* km [0-9].*"))
            .firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 30), webDump("a station row with a price"))
        // The sheet handle cycles peek, half, full; open it until the first row is on screen.
        for _ in 0..<3 where !station.isHittable && resize.exists {
            resize.tap()
            pause(2)
        }
        XCTAssertTrue(station.isHittable, webDump("a station row on screen"))
        step("open station")
        station.tap()
        pause(4)
    }

    /// The widget fuel screen from the Home Screen quick action, as a user changes it later.
    /// `XCUIApplication.open(_:)` would relaunch the app, flash a blank screen and lose the route.
    private func openWidgetFuelSettings() {
        step("home screen")
        skipAnimationWaits()
        XCUIDevice.shared.press(.home)
        pause(2)
        let icon = showPumperlyIcon()
        step("quick actions: widget fuel")
        icon.press(forDuration: 1.5)
        pause(2)
        let widgetFuel = springboard.buttons["Widget fuel"]
        XCTAssertTrue(widgetFuel.waitForExistence(timeout: 5), springboardDump("Widget fuel quick action"))
        widgetFuel.tap()
        step("widget fuel settings")
        let diesel = app.buttons["settings.fuel.B7"]
        XCTAssertTrue(diesel.waitForExistence(timeout: 15), "widget fuel screen not found\n\(app.debugDescription)")
        pause(2)
        diesel.tap()
        pause(2)
        XCTAssertTrue(closeFuelScreen(), "the widget fuel screen did not close\n\(app.debugDescription)")
        pause(1)
    }

    /// The app's icon, on whichever Home Screen page it landed.
    private func showPumperlyIcon() -> XCUIElement {
        let icon = springboard.icons["Pumperly"]
        let hittable = NSPredicate(format: "isHittable == true")
        // Animation waits are off here, so give each page time to settle before swiping on:
        // one swipe too many lands in the App Library.
        for page in 0..<3 {
            if XCTWaiter.wait(for: [expectation(for: hittable, evaluatedWith: icon)], timeout: 3) == .completed { break }
            if page < 2 { springboard.swipeLeft() }
        }
        XCTAssertTrue(icon.isHittable, springboardDump("Pumperly icon on the Home Screen"))
        return icon
    }

    private func addWidgetToHomeScreen() {
        XCUIDevice.shared.press(.home)
        pause(2)
        let icon = showPumperlyIcon()
        step("quick actions: edit Home Screen")
        icon.press(forDuration: 1.5)
        pause(2)
        let edit = springboard.buttons["Edit Home Screen"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), springboardDump("Edit Home Screen"))
        edit.tap()
        pause(2)

        step("widget gallery")
        let editButton = springboard.buttons["Edit"]
        if editButton.waitForExistence(timeout: 5) {
            editButton.tap()
            pause(1)
        }
        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), springboardDump("Add Widget"))
        addWidget.tap()
        pause(2)

        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), springboardDump("widget search field"))
        search.tap()
        search.typeText("Pumperly")
        pause(2)
        let result = springboard.cells.matching(NSPredicate(format: "label CONTAINS 'Pumperly'")).firstMatch
        let resultFallback = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Pumperly'")).firstMatch
        if result.waitForExistence(timeout: 10) { result.tap() } else {
            XCTAssertTrue(resultFallback.waitForExistence(timeout: 5), springboardDump("Pumperly in the widget gallery"))
            resultFallback.tap()
        }
        pause(3)

        step("medium widget")
        // The sizes are pages, small then medium, and the pager stops at the last one. One swipe
        // sometimes does not take while the gallery is still settling, so swipe twice.
        springboard.swipeLeft()
        pause(2)
        springboard.swipeLeft()
        pause(2)
        // The gallery runs in another process, so its button is not in SpringBoard's tree:
        // tap where it sits, at the bottom of the gallery sheet.
        let add = springboard.buttons.matching(NSPredicate(format: "label == 'Add Widget'")).firstMatch
        if add.waitForExistence(timeout: 2) {
            add.tap()
        } else {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap()
        }
        pause(2)
        // The first widget that wants location asks for it separately.
        answerAlert(button: NSPredicate(format: "label == 'Allow'"), timeout: 10, name: "widget location")
        let done = springboard.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), springboardDump("Done after adding the widget"))
        pause(2)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10), springboardDump("leaving edit mode"))

        step("widget on the Home Screen")
        pause(5)
        let needsLocation = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS 'allow location'")).firstMatch
        if needsLocation.exists {
            step("widget needs location: open the app and come back")
            needsLocation.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
            pause(3)
            XCUIDevice.shared.press(.home)
            pause(5)
        }
    }

    // MARK: - Helpers

    /// Since 0.2.0 the fuel screen sometimes ignores Done in this flow: the touches reach the
    /// app, it is idle and nothing presents the sheet again, yet it stays, and then a swipe down
    /// fails too. It never happened in isolated runs. Each attempt is checked and logged.
    @discardableResult
    private func closeFuelScreen() -> Bool {
        let done = app.buttons["settings.done"]
        let attempts: [(String, () -> Void)] = [
            ("tap", { done.tap() }),
            ("second tap", { done.tap() }),
            ("coordinate tap", { done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }),
            ("swipe down", { self.app.navigationBars.firstMatch.swipeDown(velocity: .fast) }),
        ]
        for (how, attempt) in attempts {
            // A previous attempt can close the screen after its wait ran out.
            if !done.exists { return true }
            attempt()
            if done.waitForNonExistence(timeout: 4) {
                step("fuel screen closed by \(how)")
                return true
            }
            step("fuel screen still open after \(how): Done hittable \(done.isHittable)")
        }
        return false
    }

    /// SpringBoard on the iOS 26 simulator does not report that its animations finished after a
    /// long press or on entering edit mode, so XCUITest waits 60 s before the next step. The Home
    /// Screen part skips that wait (a private XCUITest method, only in this demo test); the
    /// pauses and waitForExistence calls pace it instead.
    private func skipAnimationWaits() {
        guard let process: AnyClass = NSClassFromString("XCUIApplicationProcess") else { return }
        let selector = NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:")
        guard let method = class_getInstanceMethod(process, selector) else {
            step("cannot skip animation waits: \(selector) not found")
            return
        }
        let original = method_getImplementation(method)
        let skip: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
        method_setImplementation(method, imp_implementationWithBlock(skip))
        restoreAnimationWaits = { method_setImplementation(method, original) }
    }

    /// The first tap on the site's search box sometimes does not focus it, so tap until the
    /// keyboard is up.
    private func focus(_ field: XCUIElement) {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for attempt in 1...4 {
            if attempt < 3 { field.tap() } else { field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap() }
            let waiter = XCTWaiter.wait(for: [expectation(for: focused, evaluatedWith: field)], timeout: 3)
            if waiter == .completed || app.keyboards.firstMatch.exists {
                pause(1)
                return
            }
            step("search box not focused after tap \(attempt)")
        }
        XCTFail("the search box never took keyboard focus")
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    /// The site's single search box: "Where to?" before a route, "Destination..." after.
    private var destinationField: XCUIElement {
        let labels = ["Where to?", "¿A dónde vas?", "Destination...", "Destino..."]
        return web.textFields.matching(NSPredicate(format: "placeholderValue IN %@ OR label IN %@", labels, labels))
            .firstMatch
    }

    /// The route option ("74.9 km 50 min") in the bottom sheet once the route is drawn.
    private var routeSummary: XCUIElement {
        web.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+([.,][0-9]+)? km .*min$")).firstMatch
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Prints the step with its offset from launch, to line the video up with the flow.
    private func step(_ name: String) {
        print(String(format: "DEMO %6.1fs %@", Date().timeIntervalSince(started), name))
        // record-demo.sh reads these lines while the test runs.
        fflush(stdout)
    }

    /// Failure message plus the web view's tree, to see the site's real labels.
    private func webDump(_ what: String) -> String {
        "\(what) not found. Web view:\n\(web.debugDescription)"
    }

    /// Failure message plus the Springboard tree, which is the only way to see its real labels.
    private func springboardDump(_ what: String) -> String {
        "\(what) not found. Springboard:\n\(springboard.debugDescription)"
    }
}
