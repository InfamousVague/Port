import SwiftUI
import AppKit
import UserNotifications
import PortPane
import PortShared
import SuiteKit

// Standalone Port. Post-split this is just a host shim — the whole
// port manager (scanner, forwarder, NAT-PMP, UI, notifier) lives in
// `PortPane` so the MattsSoftware launcher can load the same code
// out of an installed Port.app. Behaviour unchanged.
@main
struct PortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate,
    UNUserNotificationCenterDelegate, NSPopoverDelegate
{
    private let pane = PortPaneProvider()
    // Optional — nil in merged-deferred mode (the launcher hosts the
    // visible Port; this process exists only to handle widget
    // AppIntents before exiting). showPopover() guards against nil.
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Register IntentBus BEFORE deciding whether to defer. The
        // widget's RefreshPortIntent declares openAppWhenRun = true,
        // so the system dispatches `perform()` to this process
        // shortly after this method returns. Hard-exiting via
        // SuiteGuard first would silence the button.
        IntentBus.shared.register { [weak self] in
            self?.pane.paneRefresh()
            self?.showPopover()
        }
        pane.paneStart()
        UNUserNotificationCenter.current().delegate = self

        if SuiteGuard.shouldDeferToHost("port") {
            // Merged. No status item; stay alive long enough for any
            // pending widget intent to fire (scanner is fast; 15s is
            // comfortably more than a real scan needs).
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                NSApp.terminate(nil)
            }
            return
        }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = pane.paneMenuBarImage()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let vc = NSViewController()
        vc.view = pane.paneMakeView()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = vc
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else { showPopover() }
    }

    private func showPopover() {
        // Nil in merged mode — bail silently. An intent that
        // triggered our launch still gets to run its work via
        // IntentBus before we exit.
        guard let statusItem, let button = statusItem.button else {
            return
        }
        popover.show(relativeTo: button.bounds, of: button,
                     preferredEdge: .minY)
        if let win = popover.contentViewController?.view.window {
            clampOnScreen(win, anchoredTo: button)
            win.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in self?.popover.performClose(nil) }
    }

    private func clampOnScreen(_ win: NSWindow, anchoredTo anchor: NSView) {
        guard let screen = anchor.window?.screen ?? NSScreen.main
        else { return }
        let vis = screen.visibleFrame
        let pad: CGFloat = 8
        var f = win.frame
        if f.maxX > vis.maxX - pad { f.origin.x = vis.maxX - pad - f.width }
        if f.minX < vis.minX + pad { f.origin.x = vis.minX + pad }
        if f.minY < vis.minY + pad { f.origin.y = vis.minY + pad }
        if f != win.frame { win.setFrame(f, display: true) }
    }

    /// `port://` deep link (e.g. opened from Stats' network panel).
    func application(_ application: NSApplication, open urls: [URL]) {
        showPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m); clickMonitor = nil
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (standalone)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) { handler([.banner, .list]) }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        let key = response.notification.request.content
            .userInfo["portKey"] as? String
        DispatchQueue.main.async {
            if let key { self.pane.paneFocus(key) }
            self.showPopover()
        }
        handler()
    }
}
