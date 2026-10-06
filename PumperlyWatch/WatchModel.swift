import SwiftUI
import WidgetKit

/// The watch list: the chosen fuel and the cheapest stations near the watch.
@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var fuel: FuelType
    /// Nil until the first load finishes.
    @Published private(set) var content: CheapestNearbyEntry.Content?
    @Published private(set) var isLoading = false

    private let settings: SharedSettings
    private var loadTask: Task<Void, Never>?

    init(settings: SharedSettings = SharedSettings()) {
        self.settings = settings
        fuel = settings.fuel
        WatchSync.shared.onFuelReceived = { [weak self] fuel in
            Task { @MainActor in self?.fuelReceived(fuel) }
        }
        WatchSync.shared.activate()
    }

    func refresh() {
        loadTask?.cancel()
        isLoading = true
        let fuel = fuel
        loadTask = Task {
            let entry = await WatchStations.loadEntry(fuel: fuel, askPermission: true, settings: settings)
            guard !Task.isCancelled else { return }
            content = entry.content
            isLoading = false
        }
    }

    /// A fuel picked on the watch.
    func select(_ newFuel: FuelType) {
        guard newFuel != fuel else { return }
        settings.fuel = newFuel
        WidgetCenter.shared.reloadAllTimelines()
        fuel = newFuel
        content = nil
        refresh()
    }

    /// A fuel sent by the iPhone, already stored by WatchSync.
    private func fuelReceived(_ newFuel: FuelType) {
        guard newFuel != fuel else { return }
        fuel = newFuel
        content = nil
        refresh()
    }
}
