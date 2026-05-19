import Foundation
import Network

/// Local TCP proxy: accepts connections on a listen endpoint and pipes each
/// one bidirectionally to a target host:port, all on Network.framework.
final class Forwarder {
    private var listeners: [String: NWListener] = [:]
    private let queue = DispatchQueue(label: "com.mattssoftware.port.forwarder")

    @discardableResult
    func start(listenHost: String, listenPort: UInt16, targetHost: String, targetPort: UInt16) throws -> String {
        let id = "\(listenHost):\(listenPort) → \(targetHost):\(targetPort)"
        guard listeners[id] == nil else { return id }
        guard let lport = NWEndpoint.Port(rawValue: listenPort),
              let tport = NWEndpoint.Port(rawValue: targetPort) else {
            throw PortError(message: "Invalid port number.")
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(listenHost), port: lport)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [queue] client in
            let upstream = NWConnection(
                host: NWEndpoint.Host(targetHost),
                port: tport,
                using: .tcp
            )
            client.start(queue: queue)
            upstream.start(queue: queue)
            Forwarder.pump(from: client, to: upstream)
            Forwarder.pump(from: upstream, to: client)
        }
        listener.start(queue: queue)
        listeners[id] = listener
        return id
    }

    func stop(_ id: String) {
        listeners[id]?.cancel()
        listeners[id] = nil
    }

    func stopAll() {
        for listener in listeners.values { listener.cancel() }
        listeners.removeAll()
    }

    private static func pump(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                from.cancel()
                to.cancel()
                return
            }
            pump(from: from, to: to)
        }
    }
}
