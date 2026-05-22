import Foundation
import WidgetKit

/// Read/write `SharedPort` in the Group Container. Host writes after
/// each `refresh()`; widget timeline reads on every refresh tick.
/// Atomic file writes so the widget never sees a half-written buffer.
public enum SharedPortStore {

    private static let filename = "shared-port.json"

    public static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(filename)
    }

    public static func write(_ state: SharedPort) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        _ = try? data.write(to: url, options: [.atomic])
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func read() -> SharedPort {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(
                  SharedPort.self, from: data)
        else { return SharedPort() }
        return state
    }
}
