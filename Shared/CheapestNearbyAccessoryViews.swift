import SwiftUI
import WidgetKit

/// Text for the Lock Screen (accessory) families of the Cheapest nearby widget. Pure functions
/// over the entry, so the tests can check them without rendering a view.
enum AccessoryText {
    static let table = "Accessory"
    static let dash = "—"

    /// The station the accessory families show: the first row, the cheapest (or nearest for EV).
    static func cheapest(_ entry: CheapestNearbyEntry) -> StationRow? {
        if case .stations(let rows) = entry.content { return rows.first }
        return nil
    }

    /// A short fuel code that fits the inline line, such as "B7" or "GLP".
    static func shortCode(_ fuel: FuelType, bundle: Bundle = .main) -> String {
        NSLocalizedString("short.\(fuel.rawValue)", tableName: table, bundle: bundle, comment: "Short fuel code")
    }

    /// The short message for an entry with no station to show, nil when there is one.
    static func message(entry: CheapestNearbyEntry, bundle: Bundle = .main) -> String? {
        let key: String
        switch entry.content {
        case .stations(let rows):
            if !rows.isEmpty { return nil }
            key = "message.empty"
        case .needsLocation: key = "message.needsLocation"
        case .empty: key = "message.empty"
        case .unavailable: key = "message.unavailable"
        }
        return NSLocalizedString(key, tableName: table, bundle: bundle, comment: "Lock Screen widget message")
    }

    /// One line, such as "B7 1,459 € · Repsol Madrid 1,1 km", or "B7 · Offline".
    static func inline(entry: CheapestNearbyEntry, bundle: Bundle = .main) -> String {
        let code = shortCode(entry.fuel, bundle: bundle)
        guard let row = cheapest(entry) else {
            return "\(code) · \(message(entry: entry, bundle: bundle) ?? dash)"
        }
        return "\(code) \(row.valueText ?? dash) · \(row.name) \(row.distanceText)"
    }

    /// The fallback when the full line does not fit: "B7 1,459 €", or the bare message.
    static func inlineCompact(entry: CheapestNearbyEntry, bundle: Bundle = .main) -> String {
        guard let row = cheapest(entry) else { return message(entry: entry, bundle: bundle) ?? dash }
        return "\(shortCode(entry.fuel, bundle: bundle)) \(row.valueText ?? dash)"
    }

    /// The number in the circle: the price without its currency ("1,459"), the power without
    /// its unit for EV ("150"), a dash when there is none.
    static func circularValue(entry: CheapestNearbyEntry) -> String {
        guard let text = cheapest(entry)?.valueText else { return dash }
        let number = String(text.filter { $0.isNumber || $0 == "," || $0 == "." })
            .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        return number.isEmpty ? dash : number
    }

    /// The unit under the number, shown for EV only: a bare price is clear on its own.
    static func circularUnit(entry: CheapestNearbyEntry) -> String? {
        guard entry.fuel == .ev, cheapest(entry)?.valueText != nil else { return nil }
        return "kW"
    }

    /// The last line of the rectangular family: "1,459 € · 1,1 km".
    static func rectangularDetail(_ row: StationRow) -> String {
        "\(row.valueText ?? dash) · \(row.distanceText)"
    }

    static func fuelSymbol(_ fuel: FuelType) -> String {
        fuel == .ev ? "bolt.car.fill" : "fuelpump.fill"
    }

    /// The same symbols the Home Screen widget shows for each message.
    static func messageSymbol(entry: CheapestNearbyEntry) -> String {
        switch entry.content {
        case .needsLocation: return "location.slash"
        case .unavailable: return "wifi.exclamationmark"
        case .empty, .stations: return "fuelpump.slash"
        }
    }
}

/// The Lock Screen families. A tap opens the same page as the Home Screen widget.
struct CheapestNearbyAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheapestNearbyEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: AccessoryCircularView(entry: entry)
            case .accessoryInline: AccessoryInlineView(entry: entry)
            default: AccessoryRectangularView(entry: entry)
            }
        }
        .widgetURL(TimelineMapping.tapURL(for: entry))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryCircularView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: CheapestNearbyEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let message = AccessoryText.message(entry: entry) {
                Image(systemName: AccessoryText.messageSymbol(entry: entry))
                    .font(.title3.weight(.semibold))
                    .accessibilityLabel(message)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: AccessoryText.fuelSymbol(entry.fuel))
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(AccessoryText.circularValue(entry: entry))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(renderingMode == .fullColor ? Color("BrandGreen") : Color.primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let unit = AccessoryText.circularUnit(entry: entry) {
                        Text(unit)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

struct AccessoryRectangularView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: CheapestNearbyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(entry.fuel.label, systemImage: AccessoryText.fuelSymbol(entry.fuel))
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            if let row = AccessoryText.cheapest(entry) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(AccessoryText.rectangularDetail(row))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(renderingMode == .fullColor ? Color("BrandGreen") : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Label(AccessoryText.message(entry: entry) ?? AccessoryText.dash,
                      systemImage: AccessoryText.messageSymbol(entry: entry))
                    .font(.body)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccessoryInlineView: View {
    let entry: CheapestNearbyEntry

    var body: some View {
        // The inline slot is narrow next to the date: fall back to the price alone.
        ViewThatFits {
            Label(AccessoryText.inline(entry: entry), systemImage: AccessoryText.fuelSymbol(entry.fuel))
            Label(AccessoryText.inlineCompact(entry: entry), systemImage: AccessoryText.fuelSymbol(entry.fuel))
        }
    }
}
