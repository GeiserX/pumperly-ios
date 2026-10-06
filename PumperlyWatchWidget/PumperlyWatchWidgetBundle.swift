import SwiftUI
import WidgetKit

@main
struct PumperlyWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CheapestNearbyComplication()
    }
}

struct CheapestNearbyComplication: Widget {
    static let kind = "CheapestNearbyWatch"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchCheapestNearbyProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName(Text("watch.widget.name", tableName: WatchText.table))
        .description(Text("watch.widget.description", tableName: WatchText.table))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
