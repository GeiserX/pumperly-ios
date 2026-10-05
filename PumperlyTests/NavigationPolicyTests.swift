import XCTest
@testable import Pumperly

final class NavigationPolicyTests: XCTestCase {
    private func decide(_ string: String, mainFrame: Bool = true) -> NavigationDecision {
        NavigationPolicy.decide(URL(string: string), isMainFrame: mainFrame)
    }

    func testPumperlyHttpsLoadsInApp() {
        XCTAssertEqual(decide("https://pumperly.com/es?station=ES:4508"), .loadInApp)
        XCTAssertEqual(decide("https://www.pumperly.com/"), .loadInApp)
        XCTAssertEqual(decide("https://PUMPERLY.com/en"), .loadInApp)
    }

    func testOtherSitesOpenOutsideTheApp() {
        XCTAssertEqual(decide("https://github.com/GeiserX/Pumperly"), .openExternally)
        XCTAssertEqual(decide("https://www.openstreetmap.org/copyright"), .openExternally)
    }

    func testLookalikeHostsAreNotTrusted() {
        XCTAssertEqual(decide("https://pumperly.com.evil.example/"), .openExternally)
        XCTAssertEqual(decide("https://evilpumperly.com/"), .openExternally)
        XCTAssertEqual(decide("https://api.pumperly.com/"), .openExternally)
        XCTAssertEqual(decide("https://pumperly.com@evil.example/"), .openExternally)
    }

    func testNonHttpsPumperlyLeavesTheApp() {
        XCTAssertEqual(decide("http://pumperly.com/"), .openExternally)
        XCTAssertFalse(NavigationPolicy.isAllowed(URL(string: "http://pumperly.com/")))
    }

    func testSystemSchemesGoToTheirApps() {
        XCTAssertEqual(decide("mailto:hello@example.com"), .openExternally)
        XCTAssertEqual(decide("tel:+34600000000"), .openExternally)
        XCTAssertEqual(decide("maps://?daddr=40.4,-3.7"), .openExternally)
    }

    func testDangerousSchemesAreCancelled() {
        XCTAssertEqual(decide("javascript:alert(1)"), .cancel)
        XCTAssertEqual(decide("file:///etc/passwd"), .cancel)
        XCTAssertEqual(decide("data:text/html,hi"), .cancel)
        XCTAssertEqual(NavigationPolicy.decide(nil, isMainFrame: true), .cancel)
    }

    func testAboutBlankLoads() {
        XCTAssertEqual(decide("about:blank"), .loadInApp)
    }

    func testSubframesStayInPlaceAndNeverLeaveTheApp() {
        XCTAssertEqual(decide("https://www.youtube.com/embed/x", mainFrame: false), .loadInApp)
        XCTAssertEqual(decide("http://example.com/", mainFrame: false), .cancel)
        XCTAssertEqual(decide("tel:+34600000000", mainFrame: false), .cancel)
    }

    func testLocationOnlyForTopLevelPumperly() {
        XCTAssertTrue(NavigationPolicy.mayShareLocation(isMainFrame: true, scheme: "https", host: "pumperly.com"))
        XCTAssertTrue(NavigationPolicy.mayShareLocation(isMainFrame: true, scheme: "HTTPS", host: "WWW.pumperly.com"))
        XCTAssertFalse(NavigationPolicy.mayShareLocation(isMainFrame: false, scheme: "https", host: "pumperly.com"))
        XCTAssertFalse(NavigationPolicy.mayShareLocation(isMainFrame: true, scheme: "http", host: "pumperly.com"))
        XCTAssertFalse(NavigationPolicy.mayShareLocation(isMainFrame: true, scheme: "https", host: "example.com"))
    }
}
