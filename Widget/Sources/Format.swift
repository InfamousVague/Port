import Foundation

/// "3 minutes ago" style relative time for the "scanned X ago" line.
func fmtAgo(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: .now)
}
