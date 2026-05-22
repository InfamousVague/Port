import WidgetKit
import SwiftUI
import PortShared

/// Port's widget: number of listening ports + top processes. Small
/// is the count + a refresh button; medium adds a top-3 rollup.
struct PortOpenWidget: Widget {
    let kind: String = "PortOpenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortProvider()) {
            entry in
            PortWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Open Ports")
        .description("Listening sockets at a glance + one-click refresh.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PortWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PortEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}
