import CoreLocation
import WidgetKit

struct CheapestNearbyProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheapestNearbyEntry {
        TimelineMapping.sample(fuel: SharedSettings().fuel)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheapestNearbyEntry) -> Void) {
        if context.isPreview {
            completion(TimelineMapping.sample(fuel: SharedSettings().fuel))
            return
        }
        Task { completion(await Self.loadEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheapestNearbyEntry>) -> Void) {
        Task {
            let entry = await Self.loadEntry()
            completion(Timeline(entries: [entry], policy: .after(TimelineMapping.nextRefresh(after: entry))))
        }
    }

    /// Live location first, then the last one the app saved; no location means no request.
    static func loadEntry(now: Date = Date()) async -> CheapestNearbyEntry {
        let settings = SharedSettings()
        let fuel = settings.fuel
        var coordinate = await WidgetLocator.currentCoordinate()
        if coordinate == nil, let saved = settings.lastLocation(now: now) {
            coordinate = CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude)
        }
        guard let coordinate else {
            return TimelineMapping.entry(date: now, fuel: fuel, result: nil)
        }
        do {
            let stations = try await StationsAPI.fetchNearest(latitude: coordinate.latitude,
                                                              longitude: coordinate.longitude, fuel: fuel)
            return TimelineMapping.entry(date: now, fuel: fuel, result: .success(stations))
        } catch {
            return TimelineMapping.entry(date: now, fuel: fuel, result: .failure(error))
        }
    }
}
