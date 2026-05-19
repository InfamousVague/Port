import Foundation
import UserNotifications

/// Thin wrapper over UserNotifications for "a new port opened" alerts.
enum Notifier {
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
        UNUserNotificationCenter.current().add(request)
    }
}
