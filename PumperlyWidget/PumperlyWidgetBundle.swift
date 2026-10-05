import SwiftUI
import WidgetKit

@main
struct PumperlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheapestNearbyWidget()
    }
}

struct CheapestNearbyWidget: Widget {
    static let kind = "CheapestNearby"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CheapestNearbyProvider()) { entry in
            CheapestNearbyView(entry: entry)
        }
        .configurationDisplayName(Text("widget.title"))
        .description(Text("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
