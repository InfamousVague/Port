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
                // Forces `.accented` in the SwiftUI subtree so any
                // adaptive code (button styles, image rendering)
                // reads the dimmed-glass mode regardless of focus.
                // Visual consistency with the rest of the family.
                .environment(\.widgetRenderingMode, .accented)
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
        Group {
            switch family {
            case .systemSmall:  SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default:            SmallView(entry: entry)
            }
        }
        // Desktop-widget tap → MattsSoftware launcher pops its
        // popover already switched to the Port pane. Without
        // this URL hook tapping the widget launches the
        // standalone Port bundle id, MenuBarExtra appears for a
        // frame, but the user has no way to target a specific
        // pane in the launcher's merged view.
        .widgetURL(URL(string: "mattssoftware://port"))
    }
}
