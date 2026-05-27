import Foundation
import UserNotifications

/// Thin wrapper over UserNotifications for "a new port opened" alerts.
enum Notifier {
    /// How long these transient "FYI" notifications linger in
    /// Notification Center after delivery before we auto-remove them.
    /// 5s mirrors the default macOS banner style — the NC entry
    /// shouldn't outlast the banner for a notification this disposable.
    /// The system banner is dismissed by macOS on its own schedule;
    /// this only governs the persistent NC entry.
    private static let autoDismissAfter: TimeInterval = 5

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func postNewPort(key: String, port: Int, proto: String, process: String, service: String?) {
        let content = UNMutableNotificationContent()
        content.title = "New \(proto.uppercased()) port \(port) opened"
        var who = process
        if let service { who += "  ·  \(service)" }
        content.body = "\(who). Click to view it in Port."
        content.userInfo = ["portKey": key, "suitePane": "port", "suiteFocus": key]
        send(id: "port-\(key)", content: content)
    }

    static func postSummary(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(count) new ports opened"
        content.body = "Click to open Port."
        send(id: "port-burst-\(Int(Date().timeIntervalSince1970))", content: content)
    }

    private static func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            // Only schedule removal if the deliver itself succeeded —
            // otherwise we'd race to clear an id that was never added.
            guard error == nil else { return }
            scheduleAutoDismiss(id: id)
        }
    }

    /// Remove the delivered notification from NC after `autoDismissAfter`.
    /// Tap-handling still works during that window (the userInfo +
    /// `didReceive` delegate path runs synchronously when the banner is
    /// clicked), so users who do catch it can still jump straight to
    /// the offending port. We just stop the NC list from filling up
    /// with stale "a port opened 3 hours ago" rows the user can't
    /// usefully act on anymore.
    private static func scheduleAutoDismiss(id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
}
