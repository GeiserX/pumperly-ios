import SwiftUI

/// The card Siri and Shortcuts show under the spoken answer.
struct CheapestNearbySnippet: View {
    let fuel: FuelType
    let answer: CheapestNearbyAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: fuel == .ev ? "bolt.car.fill" : "fuelpump.fill")
                    .foregroundStyle(Color("BrandGreen"))
                Text(fuel.label)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))

            switch answer {
            case .stations(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(row.distanceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.valueText ?? "—")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(index == 0 ? Color("BrandGreen") : Color.primary)
                    }
                }
            case .empty:
                Image(systemName: "fuelpump.slash").font(.title2).foregroundStyle(.secondary)
            case .needsLocation, .locationUnavailable:
                Image(systemName: "location.slash").font(.title2).foregroundStyle(.secondary)
            case .unavailable:
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
