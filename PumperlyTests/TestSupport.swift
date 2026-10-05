import Foundation
import XCTest

enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json", file: file, line: line)
        return try Data(contentsOf: url)
    }
}

private final class BundleToken {}
