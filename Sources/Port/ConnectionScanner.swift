import Foundation

struct Connection: Identifiable, Hashable {
    let proto: String          // "tcp"
    let localAddress: String
    let localPort: Int
    let remoteAddress: String
    let remotePort: Int
    let pid: Int32
    let process: String
    var lat: Double?
    var lon: Double?
    var city: String?
    var country: String?

    var id: String { "\(proto):\(localPort):\(remoteAddress):\(remotePort):\(pid)" }
    var isLocatable: Bool { lat != nil && lon != nil }
}

enum ConnectionScanner {
    /// Established outbound/inbound TCP connections via `lsof` field mode.
    static func scan() -> [Connection] {
        let output = run(["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-Fpcn"])
        var result: [Connection] = []
        var pid: Int32 = 0
        var command = ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let arrow = value.range(of: "->") else { continue }
                let local = String(value[value.startIndex..<arrow.lowerBound])
                let remote = String(value[arrow.upperBound...])
                guard let l = hostPort(local), let r = hostPort(remote) else { continue }
                result.append(
                    Connection(
                        proto: "tcp",
                        localAddress: l.host, localPort: l.port,
                        remoteAddress: r.host, remotePort: r.port,
                        pid: pid, process: command,
                        lat: nil, lon: nil, city: nil, country: nil
                    )
                )
            default:
                continue
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private static func run(_ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func hostPort(_ token: String) -> (host: String, port: Int)? {
        guard let colon = token.lastIndex(of: ":") else { return nil }
        var host = String(token[token.startIndex..<colon])
        guard let port = Int(token[token.index(after: colon)...]), port > 0 else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return (host, port)
    }
}

/// Best-effort geolocation of public IPs via ip-api.com (no key, batched,
/// session-cached). Private/loopback IPs are skipped — they never leave the
/// machine. This is the only outbound network call Port makes.
actor GeoIP {
    static let shared = GeoIP()
    private var cache: [String: (lat: Double, lon: Double, city: String?, country: String?)] = [:]

    func locate(_ ips: [String]) async -> [String: (lat: Double, lon: Double, city: String?, country: String?)] {
        let wanted = Set(ips).filter { isPublic($0) && cache[$0] == nil }
        if !wanted.isEmpty {
            await fetch(Array(wanted))
        }
        var out: [String: (lat: Double, lon: Double, city: String?, country: String?)] = [:]
        for ip in ips { if let v = cache[ip] { out[ip] = v } }
        return out
    }

    private func fetch(_ ips: [String]) async {
        guard let url = URL(string: "http://ip-api.com/batch?fields=status,lat,lon,city,country,query") else { return }
        let body = try? JSONSerialization.data(withJSONObject: ips.map { ["query": $0] })
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        for entry in arr {
            guard (entry["status"] as? String) == "success",
                  let ip = entry["query"] as? String,
                  let lat = entry["lat"] as? Double,
                  let lon = entry["lon"] as? Double
            else { continue }
            cache[ip] = (lat, lon, entry["city"] as? String, entry["country"] as? String)
        }
    }

    private nonisolated func isPublic(_ ip: String) -> Bool {
        if ip.contains(":") { return false }                       // skip IPv6 for geo
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        if p[0] == 10 || p[0] == 127 { return false }
        if p[0] == 192 && p[1] == 168 { return false }
        if p[0] == 172 && (16...31).contains(p[1]) { return false }
        if p[0] == 169 && p[1] == 254 { return false }
        if p[0] == 0 || p[0] >= 224 { return false }
        return true
    }
}
