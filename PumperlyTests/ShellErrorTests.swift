import XCTest
@testable import Pumperly

final class ShellErrorTests: XCTestCase {
    private func urlError(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }

    func testNetworkFailuresShowTheOfflineScreen() {
        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCannotFindHost,
                     NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost] {
            XCTAssertEqual(ShellError.classify(urlError(code)), .offline, "code \(code)")
        }
    }

    func testCertificateFailuresShowTheSSLScreen() {
        for code in [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasUnknownRoot] {
            XCTAssertEqual(ShellError.classify(urlError(code)), .ssl, "code \(code)")
        }
    }

    func testCancelledAndPolicyStoppedLoadsShowNothing() {
        XCTAssertNil(ShellError.classify(urlError(NSURLErrorCancelled)))
        XCTAssertNil(ShellError.classify(NSError(domain: "WebKitErrorDomain", code: 102)))
    }

    func testAnythingElseIsAPageError() {
        XCTAssertEqual(ShellError.classify(urlError(NSURLErrorBadServerResponse)), .page)
        XCTAssertEqual(ShellError.classify(NSError(domain: "Other", code: 1)), .page)
    }

    func testEveryScreenHasEnglishAndSpanishText() throws {
        let app = Bundle(for: ShellModel.self)
        for language in ["en", "es"] {
            let path = try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for error in ShellError.allCases {
                for part in ["title", "message", "action"] {
                    let key = "error.\(error.rawValue).\(part)"
                    XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, "\(language) \(key)")
                }
            }
            for fuel in FuelType.allCases {
                let key = "fuel.\(fuel.rawValue)"
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, "\(language) \(key)")
            }
        }
    }
}
