import WidgetKit

/// The watch counterpart of the iPhone widget's provider: the same entries and refresh
/// schedule, with the fuel and fallback position from the watch's own App Group.
struct WatchCheapestNearbyProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheapestNearbyEntry {
        TimelineMapping.sample(fuel: SharedSettings().fuel)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheapestNearbyEntry) -> Void) {
        if context.isPreview {
            completion(TimelineMapping.sample(fuel: SharedSettings().fuel))
            return
        }
        Task { completion(await WatchStations.loadEntry(fuel: SharedSettings().fuel, askPermission: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheapestNearbyEntry>) -> Void) {
        Task {
            let entry = await WatchStations.loadEntry(fuel: SharedSettings().fuel, askPermission: false)
            completion(Timeline(entries: [entry], policy: .after(TimelineMapping.nextRefresh(after: entry))))
        }
    }
}
