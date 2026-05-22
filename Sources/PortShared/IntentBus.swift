import Foundation

/// Bridge between the widget's `RefreshPortIntent` and the running
/// Port host process. The host's AppDelegate calls
/// `IntentBus.shared.register(...)` at launch with a closure that
/// drives `PortStore.refresh()`. The intent's `perform()` runs in
/// THIS process (openAppWhenRun = true), invokes the closure via
/// the bus, and Port's scanner does the actual privileged work.
///
/// No registered handler (running too early, or the host hasn't
/// launched yet) → silent no-op rather than crash.
@MainActor
public final class IntentBus {
    public static let shared = IntentBus()
    private init() {}

    private var refreshHandler: (@MainActor () -> Void)?

    public func register(refresh: @escaping @MainActor () -> Void) {
        self.refreshHandler = refresh
    }

    public func refresh() { refreshHandler?() }
}
