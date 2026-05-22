import AppKit
import SwiftUI
import SuiteKit

/// Port as a SuiteKit pane. Owns the store, vends the UI + glyph,
/// routes a tapped notification to the offending port. Both the
/// standalone shim and the launcher host talk to Port only through
/// this object.
@MainActor
public final class PortPaneProvider: NSObject, SuitePane {
    private let store = PortStore()

    public var suiteABIVersion: Int { SuiteKitABI.current }
    public var paneID: String { "port" }
    public var paneTitle: String { "PORT" }
    public var paneTintHex: String { "#2E9BD6" }

    public func paneMenuBarImage() -> NSImage { PortBrand.menuBarIcon }

    public func paneMakeView() -> NSView {
        NSHostingView(rootView: ContentView().environment(store))
    }

    public func paneStart() {
        store.start()
        Notifier.requestAuthorization()
    }

    public func paneStop() {
        // lsof poll is harmless to leave running.
    }

    public func paneFocus(_ key: String) {
        store.focusedPortKey = key
    }

    /// Trigger a scan from outside the pane (the widget's
    /// RefreshPortIntent routes here via the host's IntentBus
    /// registration).
    public func paneRefresh() { store.refresh() }
}

@_cdecl("suitePaneCreate")
public func suitePaneCreate() -> Unmanaged<AnyObject> {
    MainActor.assumeIsolated {
        Unmanaged.passRetained(PortPaneProvider())
    }
}
