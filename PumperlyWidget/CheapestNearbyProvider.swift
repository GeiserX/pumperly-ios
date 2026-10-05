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

    /// A live fix first. Only when the widget may use location but no fix came in time does the
    /// last position the app saved stand in. Without permission no position is used or sent.
    static func loadEntry(now: Date = Date()) async -> CheapestNearbyEntry {
        let settings = SharedSettings()
        let fuel = settings.fuel
        let coordinate: CLLocationCoordinate2D
        switch await WidgetLocator.locate() {
        case .coordinate(let latitude, let longitude):
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        case .unavailable:
            guard let saved = settings.lastLocation(now: now) else {
                return TimelineMapping.entry(date: now, fuel: fuel, result: nil)
            }
            coordinate = CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude)
        case .denied:
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
