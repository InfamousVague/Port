import Foundation
import Network

enum NATPMPError: LocalizedError {
    case noGateway
    case timeout
    case resultCode(UInt16)
    case malformed

    var errorDescription: String? {
        switch self {
        case .noGateway:
            return "Could not determine the router (no IPv4 default gateway)."
        case .timeout:
            return "Router didn't respond to NAT-PMP — it may be disabled or unsupported."
        case .resultCode(let c):
            return "Router refused the NAT-PMP request (result code \(c))."
        case .malformed:
            return "Malformed NAT-PMP response from the router."
        }
    }
}

/// Minimal native NAT-PMP client (RFC 6886) over UDP via Network.framework.
enum NATPMP {
    enum Proto {
        case tcp, udp
        var opcode: UInt8 { self == .udp ? 1 : 2 }
        var label: String { self == .udp ? "udp" : "tcp" }
    }

    private static let natpmpPort: UInt16 = 5351

    /// Parses the IPv4 default gateway from `route -n get default`.
    static func defaultGateway() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        for raw in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("gateway:") else { continue }
            let gw = line
                .replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespaces)
            let octets = gw.split(separator: ".")
            if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
                return gw
            }
        }
        return nil
    }

    static func externalAddress() async throws -> String {
        guard let gw = defaultGateway() else { throw NATPMPError.noGateway }
        let resp = try await exchange([0, 0], gateway: gw)
        guard resp.count >= 12 else { throw NATPMPError.malformed }
        try checkResult(resp)
        return "\(resp[8]).\(resp[9]).\(resp[10]).\(resp[11])"
    }

    @discardableResult
    static func addMapping(
        _ proto: Proto,
        internalPort: UInt16,
        externalPort: UInt16,
        lifetime: UInt32 = 3600
    ) async throws -> (external: UInt16, lifetime: UInt32) {
        guard let gw = defaultGateway() else { throw NATPMPError.noGateway }
        var pkt: [UInt8] = [0, proto.opcode, 0, 0]
        pkt += be16(internalPort)
        pkt += be16(externalPort)
        pkt += be32(lifetime)

        let resp = try await exchange(pkt, gateway: gw)
        guard resp.count >= 16 else { throw NATPMPError.malformed }
        try checkResult(resp)
        let mappedExternal = UInt16(resp[10]) << 8 | UInt16(resp[11])
        let grantedLifetime =
            UInt32(resp[12]) << 24 | UInt32(resp[13]) << 16 | UInt32(resp[14]) << 8 | UInt32(resp[15])
        return (mappedExternal, grantedLifetime)
    }

    static func removeMapping(_ proto: Proto, internalPort: UInt16) async throws {
        // RFC 6886: external port 0 + lifetime 0 deletes the mapping.
        _ = try await addMapping(proto, internalPort: internalPort, externalPort: 0, lifetime: 0)
    }

    // MARK: - UDP exchange

    private static func exchange(
        _ payload: [UInt8],
        gateway: String,
        timeout: TimeInterval = 2.0
    ) async throws -> [UInt8] {
        let connection = NWConnection(
            host: NWEndpoint.Host(gateway),
            port: NWEndpoint.Port(rawValue: natpmpPort)!,
            using: .udp
        )
        let queue = DispatchQueue(label: "com.mattssoftware.port.natpmp")

        return try await withCheckedThrowingContinuation { cont in
            let lock = NSLock()
            var done = false
            func finish(_ result: Result<[UInt8], Error>) {
                lock.lock()
                let already = done
                done = true
                lock.unlock()
                guard !already else { return }
                connection.cancel()
                cont.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(payload), completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) }
                    })
                    connection.receiveMessage { data, _, _, error in
                        if let data, !data.isEmpty {
                            finish(.success([UInt8](data)))
                        } else if let error {
                            finish(.failure(error))
                        } else {
                            finish(.failure(NATPMPError.malformed))
                        }
                    }
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(NATPMPError.timeout))
            }
        }
    }

    private static func checkResult(_ resp: [UInt8]) throws {
        let code = UInt16(resp[2]) << 8 | UInt16(resp[3])
        guard code == 0 else { throw NATPMPError.resultCode(code) }
    }

    private static func be16(_ v: UInt16) -> [UInt8] {
        [UInt8(v >> 8), UInt8(v & 0xff)]
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }
}
