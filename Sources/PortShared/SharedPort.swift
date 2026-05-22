import Foundation

/// Compact widget-facing snapshot of "what's listening right now".
/// Host writes after each refresh, widget timeline reads. Kept small
/// — process / port-count breakdown is what fits at widget size.
public struct SharedPort: Codable, Sendable, Equatable {

    /// One row of the "top processes by listening count" rollup.
    public struct ProcessRow: Codable, Sendable, Equatable, Hashable {
        public let name: String
        public let portCount: Int
        public init(name: String, portCount: Int) {
            self.name = name
            self.portCount = portCount
        }
    }

    public var totalCount: Int
    public var tcpCount: Int
    public var udpCount: Int
    /// Top 3 processes by number of ports listened on. Empty before
    /// the first scan — widget renders an empty-state instead.
    public var topProcesses: [ProcessRow]
    /// Headline number for the "recent activity" line: the most
    /// recently scanned distinct process count.
    public var sampledAt: Date

    public init(
        totalCount: Int = 0,
        tcpCount: Int = 0,
        udpCount: Int = 0,
        topProcesses: [ProcessRow] = [],
        sampledAt: Date = .distantPast
    ) {
        self.totalCount = totalCount
        self.tcpCount = tcpCount
        self.udpCount = udpCount
        self.topProcesses = topProcesses
        self.sampledAt = sampledAt
    }
}
