import SwiftUI
import WidgetKit

/// Widget views. They live in the shared sources so the app's tests can render them too.
struct CheapestNearbyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheapestNearbyEntry

    var body: some View {
        Group {
            switch entry.content {
            case .stations(let rows):
                if family == .systemSmall, let first = rows.first {
                    SmallStationView(fuel: entry.fuel, row: first)
                } else {
                    MediumStationsView(fuel: entry.fuel, rows: rows)
                }
            case .needsLocation:
                MessageView(fuel: entry.fuel, symbol: "location.slash",
                            text: NSLocalizedString("widget.needsLocation", comment: ""))
            case .empty:
                MessageView(fuel: entry.fuel, symbol: "fuelpump.slash",
                            text: NSLocalizedString("widget.empty", comment: ""))
            case .unavailable:
                MessageView(fuel: entry.fuel, symbol: "wifi.exclamationmark",
                            text: NSLocalizedString("widget.unavailable", comment: ""))
            }
        }
        .widgetURL(TimelineMapping.tapURL(for: entry))
        .containerBackground(for: .widget) { Color("WidgetBackground") }
        .environment(\.stationsAsOf, entry.asOf)
    }
}

private struct HeaderView: View {
    let fuel: FuelType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: fuel == .ev ? "bolt.car.fill" : "fuelpump.fill")
                .foregroundStyle(Color("BrandGreen"))
            Text(fuel.label)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            AsOfLabel()
        }
        .font(.caption2.weight(.semibold))
    }
}

private struct SmallStationView: View {
    let fuel: FuelType
    let row: StationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HeaderView(fuel: fuel)
            Spacer(minLength: 0)
            Text(row.valueText ?? "—")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Color("BrandGreen"))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(row.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Text(row.distanceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumStationsView: View {
    let fuel: FuelType
    let rows: [StationRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("widget.title", comment: ""))
                    .font(.caption.weight(.bold))
                Spacer()
                // Tapping the fuel name opens the app's settings to change it.
                Link(destination: AppConfig.settingsURL) { HeaderView(fuel: fuel) }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Link(destination: row.url) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(.footnote.weight(.semibold)).lineLimit(1)
                            Text(row.distanceText).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.valueText ?? "—")
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(index == 0 ? Color("BrandGreen") : Color.primary)
                    }
                }
                if index < rows.count - 1 { Divider() }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MessageView: View {
    let fuel: FuelType
    let symbol: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderView(fuel: fuel)
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
