import WebKit
import XCTest
@testable import Pumperly

final class UserAgentTests: XCTestCase {
    func testApplicationNameKeepsWebKitDefaultAndAddsToken() {
        XCTAssertEqual(UserAgent.applicationName(version: "0.1.0"), "Mobile/15E148 PumperlyiOS/0.1.0")
        XCTAssertEqual(UserAgent.widgetUserAgent(version: "0.1.0"), "PumperlyiOS/0.1.0 (Widget)")
    }

    func testBundleVersionComesFromProjectYml() {
        XCTAssertEqual(AppConfig.appVersion, "0.1.0")
    }

    /// The real web view sends the token at the end of its user agent.
    @MainActor
    func testWebViewSendsTheToken() async throws {
        let webView = ShellModel.makeWebView()
        webView.loadHTMLString("<p>ua</p>", baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        var userAgent: String?
        while Date() < deadline {
            if let ready = try? await webView.evaluateJavaScript("document.readyState") as? String, ready == "complete" {
                userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let agent = try XCTUnwrap(userAgent)
        XCTAssertTrue(agent.hasSuffix(" Mobile/15E148 PumperlyiOS/\(AppConfig.appVersion)"), agent)
        XCTAssertTrue(agent.contains("iPhone"), agent)
    }
}
