import XCTest
@testable import Pumperly

/// The watch app and its complications: targets, embedding, strings and the fuel sync.
final class WatchTargetsTests: XCTestCase {
    /// The repository root, from this file's path (tests run on the Mac that built them).
    private static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func projectYml() throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
    }

    /// The lines of one top-level target block under `targets:` (indented by two spaces).
    private func targetBlock(_ name: String, in yaml: String) throws -> String {
        let lines = yaml.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex(of: "  \(name):"), "target \(name) missing from project.yml")
        let rest = lines[(start + 1)...]
        // The block ends at the next target (two-space key) or the next top-level key.
        let end = rest.firstIndex { line in
            guard let first = line.first else { return false }
            if first != " " { return true }
            return line.hasPrefix("  ") && !line.hasPrefix("   ") && !line.dropFirst(2).hasPrefix("#")
        } ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    func testProjectListsBothWatchTargetsWithTheirBundleIds() throws {
        let yaml = try projectYml()
        let app = try targetBlock("PumperlyWatch", in: yaml)
        XCTAssertTrue(app.contains("platform: watchOS"), app)
        XCTAssertTrue(app.contains("type: application"), app)
        XCTAssertTrue(app.contains("PRODUCT_BUNDLE_IDENTIFIER: com.pumperly.app.watchkitapp\n"), app)
        XCTAssertTrue(app.contains("WKCompanionAppBundleIdentifier: com.pumperly.app\n"), app)
        XCTAssertTrue(app.contains("WKApplication: true"), app)
        XCTAssertTrue(app.contains("PROVISIONING_PROFILE_SPECIFIER: Pumperly Watch App Store"), app)
        XCTAssertTrue(app.contains("- group.com.pumperly.app"), app)

        let widget = try targetBlock("PumperlyWatchWidget", in: yaml)
        XCTAssertTrue(widget.contains("platform: watchOS"), widget)
        XCTAssertTrue(widget.contains("type: app-extension"), widget)
        XCTAssertTrue(widget.contains("PRODUCT_BUNDLE_IDENTIFIER: com.pumperly.app.watchkitapp.widget"), widget)
        XCTAssertTrue(widget.contains("NSExtensionPointIdentifier: com.apple.widgetkit-extension"), widget)
        XCTAssertTrue(widget.contains("PROVISIONING_PROFILE_SPECIFIER: Pumperly Watch Widget App Store"), widget)

        let phone = try targetBlock("Pumperly", in: yaml)
        XCTAssertTrue(phone.contains("- target: PumperlyWatch\n"), phone)
    }

    /// The built iPhone app carries the watch app, as the App Store build must.
    func testIPhoneAppEmbedsTheWatchApp() throws {
        let watchApp = Bundle.main.bundleURL.appendingPathComponent("Watch/PumperlyWatch.app")
        let info = try XCTUnwrap(Bundle(url: watchApp)?.infoDictionary, "no watch app at \(watchApp.path)")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.pumperly.app.watchkitapp")
        XCTAssertEqual(info["WKCompanionAppBundleIdentifier"] as? String, "com.pumperly.app")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, AppConfig.appVersion)
        let widget = watchApp.appendingPathComponent("PlugIns/PumperlyWatchWidget.appex")
        XCTAssertEqual(Bundle(url: widget)?.bundleIdentifier, "com.pumperly.app.watchkitapp.widget")
    }

    func testWatchStringsHaveTheSameKeysInEnglishAndSpanish() throws {
        func table(_ language: String) throws -> [String: String] {
            let url = Self.repoRoot.appendingPathComponent("PumperlyWatch/Common/Resources/\(language).lproj/Watch.strings")
            return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], url.path)
        }
        let english = try table("en")
        let spanish = try table("es")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(spanish.keys))
        XCTAssertTrue(spanish.values.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(spanish["watch.title"], "Lo más barato cerca")
    }

    func testSyncContextRoundTripsTheFuel() {
        XCTAssertEqual(WatchSync.context(for: .ev) as? [String: String], ["fuel": "EV"])
        for fuel in FuelType.allCases {
            XCTAssertEqual(WatchSync.fuel(from: WatchSync.context(for: fuel)), fuel)
        }
        XCTAssertNil(WatchSync.fuel(from: ["fuel": "KEROSENE"]))
        XCTAssertNil(WatchSync.fuel(from: [:]))
        XCTAssertNil(WatchSync.fuel(from: ["fuel": 7]))
    }

    /// A fuel picked on the watch stays until the iPhone's fuel really changes.
    func testRepeatedContextDoesNotUndoAWatchPick() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SharedSettings(defaults: defaults)
        let sync = WatchSync()

        XCTAssertEqual(sync.apply(["fuel": "E5"], settings: settings), .e5)
        XCTAssertEqual(settings.fuel, .e5)

        settings.fuel = .lpg // picked on the watch
        XCTAssertNil(sync.apply(["fuel": "E5"], settings: settings))
        XCTAssertEqual(settings.fuel, .lpg)

        XCTAssertEqual(sync.apply(["fuel": "B7"], settings: settings), .b7)
        XCTAssertEqual(settings.fuel, .b7)

        XCTAssertNil(sync.apply(["fuel": "nonsense"], settings: settings))
        XCTAssertNil(sync.apply([:], settings: settings))
        XCTAssertEqual(settings.fuel, .b7)
    }
}
