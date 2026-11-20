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
        let shell = ShellModel()
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
        let shell = ShellModel()
        shell.start(restoredURL: page, restoredPendingURL: page, restoredError: .offline)
        shell.applyFirstRunChoice(.e5)
        XCTAssertEqual(shell.pendingURL, page)
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
