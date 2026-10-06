import SwiftUI
import WidgetKit

/// What every complication family shows, worked out once from the entry.
struct ComplicationSummary: Equatable {
    let symbol: String
    /// The cheapest price (or charger power), or a dash.
    let value: String
    /// The station's name, or a short status.
    let detail: String
    /// The station's distance; nil for a status.
    let distance: String?

    init(entry: CheapestNearbyEntry) {
        switch entry.content {
        case .stations(let rows):
            let first = rows.first
            symbol = entry.fuel.watchSymbol
            value = first?.valueText ?? "—"
            detail = first?.name ?? ""
            distance = first?.distanceText
        case .needsLocation:
            symbol = "location.slash"
            value = "—"
            detail = WatchText.string("watch.short.needsLocation")
            distance = nil
        case .empty:
            symbol = "fuelpump.slash"
            value = "—"
            detail = WatchText.string("watch.short.empty")
            distance = nil
        case .unavailable:
            symbol = "wifi.exclamationmark"
            value = "—"
            detail = WatchText.string("watch.short.offline")
            distance = nil
        }
    }

    /// The value without its currency or unit, for the small round face: "1,459 €" becomes "1,459".
    var compactValue: String {
        let kept = value.filter { $0.isNumber || $0 == "," || $0 == "." }
        return kept.isEmpty ? value : kept
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheapestNearbyEntry

    var body: some View {
        let summary = ComplicationSummary(entry: entry)
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: summary.symbol)
                            .font(.caption2)
                            .widgetAccentable()
                        Text(summary.compactValue)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .padding(4)
                }
            case .accessoryCorner:
                Image(systemName: summary.symbol)
                    .font(.title3)
                    .widgetAccentable()
                    .widgetLabel {
                        Text(summary.distance == nil ? summary.detail : summary.value)
                    }
            case .accessoryInline:
                Label {
                    Text(summary.distance == nil ? summary.detail : "\(summary.value) \(summary.detail)")
                } icon: {
                    Image(systemName: summary.symbol)
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.fuel.watchSymbol)
                            .widgetAccentable()
                        Text(entry.fuel.label)
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(summary.value)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text([summary.detail, summary.distance].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
