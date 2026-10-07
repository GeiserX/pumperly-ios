import SwiftUI

struct ErrorView: View {
    let error: ShellError
    let action: () -> Void
    private let loadSnapshot: () -> StationCache.Snapshot?
    @State private var snapshot: StationCache.Snapshot?

    /// `loadSnapshot` reads the last known stations shown under a connectivity error.
    init(error: ShellError, action: @escaping () -> Void,
         loadSnapshot: @escaping () -> StationCache.Snapshot? = OfflineStations.load) {
        self.error = error
        self.action = action
        self.loadSnapshot = loadSnapshot
    }

    var body: some View {
        // Centred like before; scrolls only when the cached rows do not fit (large text, small screens).
        GeometryReader { geometry in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color("LaunchBackground"), ignoresSafeAreaEdges: [])
        .task(id: error) {
            snapshot = OfflineStations.showsCache(for: error) ? loadSnapshot() : nil
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color("BrandGreen"))
            Text(error.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("shell.error.title")
            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let snapshot, !OfflineStations.stations(in: snapshot).isEmpty {
                OfflineStationsView(snapshot: snapshot)
            }
            Button(action: action) {
                Text(error.action)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandGreen"))
            .padding(.top, 8)
            .accessibilityIdentifier("shell.error.action")
        }
        .padding(32)
    }

    private var symbol: String {
        switch error {
        case .offline: return "wifi.slash"
        case .ssl: return "lock.slash"
        case .page: return "exclamationmark.triangle"
        }
    }
}

/// The last known stations, offered when the site cannot be reached.
enum OfflineStations {
    static let tableName = "Offline"

    /// Only a connectivity failure gets the cached stations; a certificate or page error does not.
    static func showsCache(for error: ShellError) -> Bool {
        error == .offline
    }

    static func load() -> StationCache.Snapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PUMPERLY_UITEST_OFFLINE_CACHE"] == "1" {
            return StationCache.Snapshot(savedAt: Date().addingTimeInterval(-20 * 60), fuel: .b7,
                                         latitude: 40.405, longitude: -3.703, stations: TimelineMapping.sampleStations)
        }
        #endif
        return StationCache.appGroup?.load()
    }

    /// The rows to show, in the widget's order: cheapest first, nearest first for EV.
    static func stations(in snapshot: StationCache.Snapshot) -> [Station] {
        TimelineMapping.topStations(from: snapshot.stations, fuel: snapshot.fuel)
    }

    static func header(for snapshot: StationCache.Snapshot, now: Date = Date(), locale: Locale = .current) -> String {
        let key = snapshot.fuel.hasPrice ? "offline.header" : "offline.header.ev"
        let format = NSLocalizedString(key, tableName: tableName, comment: "Offline screen: last known stations, with the time")
        return String(format: format, TimelineMapping.asOfText(snapshot.savedAt, now: now, locale: locale))
    }

    /// Apple Maps at the station, with its name as the pin label.
    static func mapsURL(for station: Station) -> URL {
        var components = URLComponents()
        components.scheme = "maps"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(station.latitude),\(station.longitude)"),
            URLQueryItem(name: "q", value: TimelineMapping.displayName(station)),
        ]
        return components.url!
    }
}

private struct OfflineStationsView: View {
    let snapshot: StationCache.Snapshot
    @Environment(\.openURL) private var openURL

    var body: some View {
        let stations = OfflineStations.stations(in: snapshot)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(OfflineStations.header(for: snapshot))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("offline.header")
                Text(snapshot.fuel.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                let row = TimelineMapping.row(for: station, fuel: snapshot.fuel)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(row.distanceText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(row.valueText ?? "—")
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(index == 0 ? Color("BrandGreen") : Color.primary)
                    Button {
                        openURL(OfflineStations.mapsURL(for: station))
                    } label: {
                        Label(NSLocalizedString("offline.openInMaps", tableName: OfflineStations.tableName,
                                                comment: "Button: open the station in Apple Maps"),
                              systemImage: "map")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color("BrandGreen"))
                    .accessibilityIdentifier("offline.maps.\(station.id)")
                }
                .accessibilityIdentifier("offline.row.\(station.id)")
                if index < stations.count - 1 { Divider() }
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
    }
}
