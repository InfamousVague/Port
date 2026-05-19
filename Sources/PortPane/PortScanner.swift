import Foundation

enum PortScanner {
    /// Scans listening TCP sockets and bound UDP sockets via `lsof` field mode.
    static func scan() -> [OpenPort] {
        var rows: [OpenPort] = []
        rows += parse(run(["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]), proto: "tcp")
        rows += parse(run(["-nP", "-iUDP", "-Fpcn"]), proto: "udp")

        var seen = Set<String>()
        return rows
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.port, $0.proto) < ($1.port, $1.proto) }
    }

    private static func run(_ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// lsof `-F` emits one field per line: `p<pid>`, `c<command>`, `n<name>`.
    private static func parse(_ output: String, proto: String) -> [OpenPort] {
        var result: [OpenPort] = []
        var pid: Int32 = 0
        var command = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value) ?? 0
            case "c":
                command = value
            case "n":
                if value.contains("->") { continue }       // skip established conns
                guard let hp = splitHostPort(value) else { continue }
                result.append(
                    OpenPort(
                        proto: proto,
                        address: hp.host,
                        port: hp.port,
                        pid: pid,
                        process: command
                    )
                )
            default:
                continue
            }
        }
        return result
    }

    /// Handles `127.0.0.1:5180`, `*:6463`, `[::1]:631`, `[fe80::1]:546`.
    private static func splitHostPort(_ token: String) -> (host: String, port: Int)? {
        guard let colon = token.lastIndex(of: ":") else { return nil }
        var host = String(token[token.startIndex..<colon])
        let portStr = String(token[token.index(after: colon)...])
        guard let port = Int(portStr), port > 0 else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.isEmpty || host == "*" { host = "*" }
        return (host, port)
    }
}
