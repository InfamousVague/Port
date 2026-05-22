import Foundation

/// Shared App Group id used by both the Port host (pane + standalone)
/// AND the widget extension to point at the same Group Container.
/// Must match `PortWidgets.entitlements`' application-groups entry
/// and the host's `Port.entitlements` group; drift silently empties
/// the Group Container URL and the widget reads stale defaults.
public enum AppGroup {
    public static let id =
        "F6ZAL7ANAD.group.com.mattssoftware.port"

    public static var containerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
