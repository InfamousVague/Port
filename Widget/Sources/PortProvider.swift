import WidgetKit
import PortShared

struct PortEntry: TimelineEntry {
    let date: Date
    let state: SharedPort
    var isStale: Bool { Date().timeIntervalSince(state.sampledAt) > 60 }
}

/// Timeline provider — reads SharedPort each refresh. Host writes
/// invalidate the timeline whenever a new scan lands; this 60s
/// refresh is the safety net for when nothing's invalidated.
struct PortProvider: TimelineProvider {

    func placeholder(in context: Context) -> PortEntry {
        PortEntry(date: .now, state: SharedPort())
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (PortEntry) -> Void) {
        completion(PortEntry(date: .now,
                             state: SharedPortStore.read()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PortEntry>) -> Void)
    {
        let entry = PortEntry(date: .now,
                              state: SharedPortStore.read())
        let nextRefresh = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry],
                            policy: .after(nextRefresh)))
    }
}
