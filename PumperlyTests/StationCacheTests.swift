import XCTest
@testable import Pumperly

final class StationCacheTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let madrid = TimeZone(identifier: "Europe/Madrid")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var directory: URL!
    private var cache: StationCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = StationCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func snapshot(fuel: FuelType = .b7, savedAt: Date? = nil, stations: [Station]? = nil,
                          latitude: Double = 40.416775, longitude: Double = -3.703790) throws -> StationCache.Snapshot {
        StationCache.Snapshot(savedAt: savedAt ?? now, fuel: fuel, latitude: latitude, longitude: longitude,
                              stations: try stations ?? StationsAPI.decode(Fixture.data("nearest-b7")))
    }

    // MARK: Cache file

    func testRoundTripKeepsStationsAndRoundsThePosition() throws {
        let saved = try snapshot()
        try cache.save(saved)
        XCTAssertEqual(cache.fileURL.lastPathComponent, "nearest-cache.json")
        let loaded = try XCTUnwrap(cache.load(now: now))
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.stations.count, 5)
        XCTAssertEqual(loaded.latitude, 40.417)
        XCTAssertEqual(loaded.longitude, -3.704)
        XCTAssertEqual(loaded.savedAt, now)
    }

    func testSnapshotsOlderThanADayAreIgnored() throws {
        try cache.save(try snapshot())
        XCTAssertNotNil(cache.load(now: now.addingTimeInterval(23 * 3600)))
        XCTAssertNotNil(cache.load(now: now.addingTimeInterval(24 * 3600)))
        XCTAssertNil(cache.load(now: now.addingTimeInterval(24 * 3600 + 1)))
        // A snapshot from the future (the clock moved back) is not shown either.
        XCTAssertNil(cache.load(now: now.addingTimeInterval(-3600)))
    }

    func testAnotherFuelIsIgnored() throws {
        try cache.save(try snapshot(fuel: .b7))
        XCTAssertNil(cache.load(fuel: .e5, now: now))
        XCTAssertNotNil(cache.load(fuel: .b7, now: now))
    }

    func testMissingOrCorruptFileReadsAsNoSnapshot() throws {
        XCTAssertNil(cache.load(now: now))
        try Data("{\"savedAt\": \"not a date\"".utf8).write(to: cache.fileURL)
        XCTAssertNil(cache.load(now: now))
        try Data([0xFF, 0x00, 0x13]).write(to: cache.fileURL)
        XCTAssertNil(cache.load(now: now))
    }

    func testClearRemovesTheFile() throws {
        try cache.save(try snapshot())
        cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL.path))
        XCTAssertNil(cache.load(now: now))
        cache.clear() // clearing twice is harmless
    }

    func testDistanceAndNearness() throws {
        // Puerta del Sol to Atocha station is about 1.7 km.
        XCTAssertEqual(StationCache.distanceKm(40.4169, -3.7035, 40.4066, -3.6892), 1.66, accuracy: 0.05)
        let saved = try snapshot()
        XCTAssertTrue(saved.isNear(latitude: 40.42, longitude: -3.70))
        XCTAssertFalse(saved.isNear(latitude: 41.39, longitude: 2.17)) // Barcelona
    }

    // MARK: Widget entries from the cache

    func testEntryFromSnapshotSetsAsOfAndKeepsTheWidgetOrder() throws {
        let saved = try snapshot()
        let entry = TimelineMapping.entry(date: now.addingTimeInterval(600), snapshot: saved, locale: english)
        XCTAssertEqual(entry.asOf, now)
        XCTAssertEqual(entry.fuel, .b7)
        guard case .stations(let rows) = entry.content else { return XCTFail("expected stations") }
        let live = TimelineMapping.rows(from: saved.stations, fuel: .b7, locale: english)
        XCTAssertEqual(rows, live)
        XCTAssertEqual(rows.map(\.name), ["Shell Madrid", "Repsol Madrid", "Blanca Madrid"])
    }

    func testEmptySnapshotReadsAsUnavailable() throws {
        let entry = TimelineMapping.entry(date: now, snapshot: try snapshot(stations: []))
        XCTAssertEqual(entry.content, .unavailable)
    }

    func testFailedFetchFallsBackToAFreshCache() throws {
        let saved = try snapshot()
        let entry = TimelineMapping.entry(date: now.addingTimeInterval(3600), fuel: .b7,
                                          result: .failure(URLError(.notConnectedToInternet)),
                                          cached: saved, near: (40.417, -3.704), locale: english)
        guard case .stations(let rows) = entry.content else { return XCTFail("expected cached stations") }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(entry.asOf, now)
        // Cached rows still mean the fetch failed, so the widget tries again soon.
        XCTAssertEqual(TimelineMapping.nextRefresh(after: entry), entry.date.addingTimeInterval(15 * 60))
    }

    func testFailedFetchWithStaleCacheIsUnavailable() throws {
        let stale = try snapshot(savedAt: now.addingTimeInterval(-25 * 3600))
        let entry = TimelineMapping.entry(date: now, fuel: .b7, result: .failure(URLError(.timedOut)),
                                          cached: stale, near: (40.417, -3.704))
        XCTAssertEqual(entry.content, .unavailable)
        XCTAssertNil(entry.asOf)
    }

    func testFallbackNeedsTheSameFuelAndANearbyPosition() throws {
        let failure: Result<[Station], Error> = .failure(URLError(.timedOut))
        let otherFuel = TimelineMapping.entry(date: now, fuel: .e5, result: failure, cached: try snapshot(fuel: .b7))
        XCTAssertEqual(otherFuel.content, .unavailable)
        let farAway = TimelineMapping.entry(date: now, fuel: .b7, result: failure, cached: try snapshot(),
                                            near: (41.39, 2.17))
        XCTAssertEqual(farAway.content, .unavailable)
        let noCache = TimelineMapping.entry(date: now, fuel: .b7, result: failure, cached: nil)
        XCTAssertEqual(noCache.content, .unavailable)
    }

    func testLiveResultsIgnoreTheCache() throws {
        let saved = try snapshot()
        let live = TimelineMapping.entry(date: now, fuel: .b7, result: .success([]), cached: saved)
        XCTAssertEqual(live.content, .empty)
        XCTAssertNil(live.asOf)
        let noLocation = TimelineMapping.entry(date: now, fuel: .b7, result: nil, cached: saved)
        XCTAssertEqual(noLocation.content, .needsLocation)
    }

    func testExistingEntriesHaveNoAsOf() {
        XCTAssertNil(TimelineMapping.sample(date: now).asOf)
        XCTAssertNil(CheapestNearbyEntry(date: now, fuel: .b7, content: .empty).asOf)
    }

    func testAsOfShowsTheTimeTodayAndTheWeekdayBefore() {
        let spanish = Locale(identifier: "es_ES")
        // 1_790_000_000 is 2026-09-21 16:13:20 in Madrid.
        XCTAssertEqual(TimelineMapping.asOfText(now, now: now.addingTimeInterval(600), locale: spanish, timeZone: madrid),
                       "16:13")
        let yesterday = TimelineMapping.asOfText(now, now: now.addingTimeInterval(20 * 3600), locale: spanish, timeZone: madrid)
        XCTAssertTrue(yesterday.contains("16:13"), yesterday)
        XCTAssertTrue(yesterday.lowercased().contains("lun"), yesterday)
    }

    // MARK: App prefetch throttle

    func testPrefetchThrottle() {
        let last = NearbyPrefetcher.Attempt(date: now, latitude: 40.4169, longitude: -3.7035)
        func check(after seconds: TimeInterval, latitude: Double = 40.4169, longitude: Double = -3.7035) -> Bool {
            NearbyPrefetcher.shouldFetch(latitude: latitude, longitude: longitude,
                                         now: now.addingTimeInterval(seconds), last: last)
        }
        XCTAssertTrue(NearbyPrefetcher.shouldFetch(latitude: 40.4, longitude: -3.7, now: now, last: nil))
        XCTAssertFalse(check(after: 5 * 60), "same place, 5 minutes later")
        XCTAssertTrue(check(after: 15 * 60), "15 minutes later")
        XCTAssertFalse(check(after: 5 * 60, latitude: 40.4210), "moved about 450 m")
        XCTAssertTrue(check(after: 2 * 60, latitude: 40.4066, longitude: -3.6892), "moved about 1.7 km")
        XCTAssertFalse(check(after: 30, latitude: 40.4066, longitude: -3.6892), "moved, but within a minute")
        XCTAssertTrue(check(after: -3600), "the clock moved back")
    }

    // MARK: Offline screen

    func testOfflineScreenOnlyForConnectivityErrors() {
        XCTAssertTrue(OfflineStations.showsCache(for: .offline))
        XCTAssertFalse(OfflineStations.showsCache(for: .ssl))
        XCTAssertFalse(OfflineStations.showsCache(for: .page))
    }

    func testOfflineScreenListsUpToThreeStationsInWidgetOrder() throws {
        let saved = try snapshot()
        XCTAssertEqual(OfflineStations.stations(in: saved).map(\.externalId), ["4711", "3218", "4508"])
        let ev = try snapshot(fuel: .ev, stations: StationsAPI.decode(Fixture.data("nearest-ev")).reversed())
        XCTAssertEqual(OfflineStations.stations(in: ev).map(\.powerKw), [360, 50, 7])
    }

    func testOfflineHeaderNamesTheTime() throws {
        let header = OfflineStations.header(for: try snapshot(), now: now.addingTimeInterval(60), locale: english)
        XCTAssertFalse(header.contains("%@"), header)
        XCTAssertTrue(header.contains(TimelineMapping.asOfText(now, now: now.addingTimeInterval(60), locale: english)), header)
    }

    func testMapsLinkOpensAppleMapsAtTheStation() throws {
        let station = try XCTUnwrap(StationsAPI.decode(Fixture.data("nearest-b7")).first)
        let url = OfflineStations.mapsURL(for: station)
        XCTAssertEqual(url.absoluteString, "maps://?ll=40.405278,-3.703139&q=Blanca%20Madrid")
    }

    func testOfflineStringsExistInEnglishAndSpanish() throws {
        let app = Bundle(for: ShellModel.self)
        var tables: [String: [String: String]] = [:]
        for language in ["en", "es"] {
            let path = try XCTUnwrap(app.path(forResource: "Offline", ofType: "strings", inDirectory: nil,
                                              forLocalization: language), language)
            tables[language] = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], language)
        }
        let enTable = try XCTUnwrap(tables["en"]), esTable = try XCTUnwrap(tables["es"])
        XCTAssertFalse(enTable.isEmpty)
        XCTAssertEqual(Set(enTable.keys), Set(esTable.keys))
        for (key, value) in enTable {
            XCTAssertEqual(value.contains("%@"), esTable[key]?.contains("%@"), key)
            XCTAssertNotEqual(value, esTable[key], "\(key) is not translated")
        }
    }
}
