import AppIntents
import XCTest
@testable import Pumperly

@MainActor
final class IntentsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let english = Locale(identifier: "en_US")

    override func setUp() {
        suite = "test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private var englishBundle: Bundle {
        get throws {
            let app = Bundle(for: ShellModel.self)
            return try XCTUnwrap(app.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        }
    }

    private func station(_ id: String, name: String, price: Double?, km: Double, kw: Double? = nil) -> Station {
        Station(id: id, externalId: id, country: "ES", name: name, brand: nil, city: "Madrid",
                latitude: 40.4, longitude: -3.7, price: price, currency: "EUR", distanceKm: km, powerKw: kw)
    }

    private func lookup(_ fuel: FuelType, location: OneShotLocator.Outcome,
                        result: Result<[Station], Error>,
                        settings: SharedSettings? = nil) async -> (CheapestNearbyAnswer, [Double]) {
        var sent: [Double] = []
        let answer = await CheapestNearbyLookup.run(
            fuel: fuel, settings: settings ?? SharedSettings(defaults: defaults), locale: english,
            locate: { location },
            fetch: { latitude, longitude, _ in
                sent = [latitude, longitude]
                return try result.get()
            })
        return (answer, sent)
    }

    // MARK: FuelChoice

    func testFuelChoiceCoversEveryFuelTypeAndRoundTrips() {
        XCTAssertEqual(FuelChoice.allCases.map(\.rawValue), FuelType.allCases.map(\.rawValue))
        for fuel in FuelType.allCases {
            XCTAssertEqual(FuelChoice(fuel).fuel, fuel)
            XCTAssertEqual(FuelChoice(fuel).rawValue, fuel.rawValue)
        }
    }

    func testFuelChoiceTitlesAreTheAppsFuelNames() {
        for choice in FuelChoice.allCases {
            let title = try? XCTUnwrap(FuelChoice.caseDisplayRepresentations[choice]).title
            XCTAssertEqual(title.map { String(localized: $0) }, choice.fuel.label, choice.rawValue)
        }
    }

    // MARK: CheapestNearbyIntent

    func testPricedFuelAnswersWithTheCheapestStation() async throws {
        let stations = [station("1", name: "Blanca Madrid", price: 1.472, km: 0.4),
                        station("2", name: "Repsol Madrid", price: 1.459, km: 1.1),
                        station("3", name: "No price", price: nil, km: 0.1)]
        let (answer, sent) = await lookup(.b7, location: .coordinate(latitude: 40.4, longitude: -3.7),
                                          result: .success(stations))
        XCTAssertEqual(sent, [40.4, -3.7])
        XCTAssertEqual(answer, .stations(TimelineMapping.rows(from: stations, fuel: .b7, locale: english)))
        guard case .stations(let rows) = answer else { return XCTFail("no stations") }
        XCTAssertEqual(rows.first?.name, "Repsol Madrid")
        let text = CheapestNearbyLookup.dialog(for: answer, fuel: .b7, bundle: try englishBundle)
        XCTAssertEqual(text, "Cheapest \(FuelType.b7.label) near you: Repsol Madrid, €1.459 per litre, 1.1 km away.")
    }

    func testGasSoldByWeightNamesNoUnit() throws {
        let rows = TimelineMapping.rows(from: [station("1", name: "GNC Vallecas", price: 1.299, km: 2)],
                                        fuel: .cng, locale: english)
        let text = CheapestNearbyLookup.dialog(for: .stations(rows), fuel: .cng, bundle: try englishBundle)
        XCTAssertEqual(text, "Cheapest \(FuelType.cng.label) near you: GNC Vallecas, €1.299, 2.0 km away.")
    }

    func testEVAnswersWithTheNearestChargerAndItsPower() async throws {
        let stations = [station("1", name: "Far fast", price: nil, km: 3.2, kw: 350),
                        station("2", name: "Iberdrola Atocha", price: nil, km: 0.4, kw: 150)]
        let (answer, _) = await lookup(.ev, location: .coordinate(latitude: 40.4, longitude: -3.7),
                                       result: .success(stations))
        let text = CheapestNearbyLookup.dialog(for: answer, fuel: .ev, bundle: try englishBundle)
        XCTAssertEqual(text, "Nearest charger: Iberdrola Atocha, 150 kW, 0.4 km away.")

        let noPower = TimelineMapping.rows(from: [station("3", name: "Slow", price: nil, km: 1, kw: nil)],
                                           fuel: .ev, locale: english)
        XCTAssertEqual(CheapestNearbyLookup.dialog(for: .stations(noPower), fuel: .ev, bundle: try englishBundle),
                       "Nearest charger: Slow, 1.0 km away.")
    }

    func testEmptyResultsSayNothingSellsTheFuel() async throws {
        let (answer, _) = await lookup(.h2, location: .coordinate(latitude: 40.4, longitude: -3.7),
                                       result: .success([station("1", name: "No price", price: nil, km: 1)]))
        XCTAssertEqual(answer, .empty)
        XCTAssertEqual(CheapestNearbyLookup.dialog(for: answer, fuel: .h2, bundle: try englishBundle),
                       "No stations with \(FuelType.h2.label) within \(Int(StationsAPI.radiusKm)) km.")
    }

    func testDeniedLocationSendsNothingAndAsksToAllowIt() async throws {
        let settings = SharedSettings(defaults: defaults)
        settings.saveLocation(latitude: 40.4, longitude: -3.7)
        let (answer, sent) = await lookup(.b7, location: .denied, result: .success([]), settings: settings)
        XCTAssertEqual(answer, .needsLocation)
        XCTAssertEqual(sent, [], "a denied location must not fall back to the saved one")
        XCTAssertEqual(CheapestNearbyLookup.dialog(for: answer, fuel: .b7, bundle: try englishBundle),
                       "Open Pumperly and allow location to find stations near you.")
    }

    func testUnavailableFixFallsBackToTheSavedLocation() async {
        let settings = SharedSettings(defaults: defaults)
        settings.saveLocation(latitude: 40.416775, longitude: -3.703790)
        let (answer, sent) = await lookup(.b7, location: .unavailable,
                                          result: .success([station("1", name: "A", price: 1.5, km: 1)]),
                                          settings: settings)
        XCTAssertEqual(sent, [40.417, -3.704])
        guard case .stations = answer else { return XCTFail("expected stations, got \(answer)") }

        settings.clearLocation()
        let (none, nothingSent) = await lookup(.b7, location: .unavailable, result: .success([]))
        XCTAssertEqual(none, .locationUnavailable)
        XCTAssertEqual(nothingSent, [])
    }

    func testNetworkFailureSaysPricesAreUnavailable() async throws {
        let (answer, _) = await lookup(.b7, location: .coordinate(latitude: 40.4, longitude: -3.7),
                                       result: .failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(answer, .unavailable)
        XCTAssertEqual(CheapestNearbyLookup.dialog(for: answer, fuel: .b7, bundle: try englishBundle),
                       "Prices are unavailable right now. Try again later.")
    }

    // MARK: SetWidgetFuelIntent

    func testSetWidgetFuelWritesTheSuiteAndReloadsTheWidget() throws {
        let settings = SharedSettings(defaults: defaults)
        XCTAssertFalse(settings.hasChosenFuel)
        var reloads = 0
        SetWidgetFuelIntent(fuel: .lpg).apply(to: settings, reload: { reloads += 1 })
        XCTAssertEqual(SharedSettings(defaults: defaults).fuel, .lpg)
        XCTAssertTrue(SharedSettings(defaults: defaults).hasChosenFuel)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(SetWidgetFuelIntent.dialog(for: .lpg, bundle: try englishBundle),
                       "The widget now shows \(FuelType.lpg.label).")
    }

    // MARK: Strings

    func testIntentStringTablesHaveTheSameKeysInEnglishAndSpanish() throws {
        let app = Bundle(for: ShellModel.self)
        for table in ["Intents", "AppShortcuts"] {
            var keys: [String: Set<String>] = [:]
            for language in ["en", "es"] {
                let url = try XCTUnwrap(app.url(forResource: table, withExtension: "strings",
                                                subdirectory: nil, localization: language),
                                        "\(language) \(table).strings")
                let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
                XCTAssertFalse(strings.isEmpty, "\(language) \(table)")
                keys[language] = Set(strings.keys)
            }
            XCTAssertEqual(keys["en"], keys["es"], table)
        }
    }

    /// The open intent restores the last page; neither it nor any phrase may promise route planning.
    func testOpenIntentPromisesNoScreenItCannotOpen() throws {
        XCTAssertEqual(PumperlyScreen.allCases, [.app])
        let app = Bundle(for: ShellModel.self)
        for (language, banned) in [("en", ["planner", "route"]), ("es", ["planificador", "ruta"])] {
            func table(_ name: String) throws -> [String: String] {
                let url = try XCTUnwrap(app.url(forResource: name, withExtension: "strings",
                                                subdirectory: nil, localization: language))
                return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            }
            let intents = try table("Intents")
            var texts = try ["intent.open.title", "intent.open.description", "param.screen", "screen.app",
                             "shortcut.open"].map { try XCTUnwrap(intents[$0], "\(language) \($0)") }
            texts += try table("AppShortcuts").values
            for text in texts {
                for word in banned {
                    XCTAssertFalse(text.lowercased().contains(word), "\(language): \(text)")
                }
            }
        }
    }

    func testEveryShortcutPhraseNamesTheApp() throws {
        let app = Bundle(for: ShellModel.self)
        for language in ["en", "es"] {
            let url = try XCTUnwrap(app.url(forResource: "AppShortcuts", withExtension: "strings",
                                            subdirectory: nil, localization: language))
            let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            for (key, phrase) in strings {
                XCTAssertTrue(phrase.contains("${applicationName}"), "\(language) \(key)")
                XCTAssertEqual(key.contains("${fuel}"), phrase.contains("${fuel}"), "\(language) \(key)")
            }
        }
    }
}
