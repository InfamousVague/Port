import Foundation
import Observation
import AppKit

struct OpenPort: Identifiable, Hashable {
    let proto: String      // "tcp" | "udp"
    let address: String
    let port: Int
    let pid: Int32
    let process: String

    var id: String { "\(proto):\(address):\(port):\(pid)" }
}

struct ActiveForward: Identifiable, Hashable {
    let id: String
    let listenHost: String
    let listenPort: UInt16
    let targetHost: String
    let targetPort: UInt16
}

struct ExternalMapping: Identifiable, Hashable {
    let id: String
    let proto: String
    let internalPort: UInt16
    let externalPort: UInt16
    let lifetime: UInt32
}

@MainActor
@Observable
final class PortStore {
    var ports: [OpenPort] = []
    var forwards: [ActiveForward] = []
    var pausedPIDs: Set<Int32> = []
    var connections: [Connection] = []
    var hostname: String = "—"
    var primaryIP: String = "—"
    var externalIP: String?
    var mappings: [ExternalMapping] = []
    var lastError: String?

    static let blipBundleID = "com.infamousvague.blip"
    // GitHub Pages mirror of the mattssoftware site (the custom domain is
    // served off-repo from a VPS — swap here if you want the apex domain).
    static let blipSiteURL = URL(string: "https://infamousvague.github.io/mattssoftware/blip")!

    var blipInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: PortStore.blipBundleID) != nil
    }

    @ObservationIgnored private let forwarder = Forwarder()
    @ObservationIgnored private var timer: Timer?

    func start() {
        let addr = LocalAddress.current()
        hostname = addr.hostname
        primaryIP = addr.primary ?? "offline"
        refresh()
        refreshConnections()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.refreshConnections()
            }
        }
        Task { await loadExternalIP() }
    }

    func loadExternalIP() async {
        externalIP = try? await NATPMP.externalAddress()
    }

    func mapExternal(proto: NATPMP.Proto, internalPort: UInt16, externalPort: UInt16) async {
        do {
            let result = try await NATPMP.addMapping(
                proto, internalPort: internalPort, externalPort: externalPort
            )
            let id = "\(proto.label):\(internalPort) → :\(result.external)"
            mappings.removeAll { $0.id == id }
            mappings.append(
                ExternalMapping(
                    id: id,
                    proto: proto.label,
                    internalPort: internalPort,
                    externalPort: result.external,
                    lifetime: result.lifetime
                )
            )
            if externalIP == nil {
                externalIP = try? await NATPMP.externalAddress()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unmapExternal(_ mapping: ExternalMapping) async {
        do {
            let proto: NATPMP.Proto = mapping.proto == "udp" ? .udp : .tcp
            try await NATPMP.removeMapping(proto, internalPort: mapping.internalPort)
            mappings.removeAll { $0.id == mapping.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshConnections() {
        Task.detached {
            var conns = ConnectionScanner.scan()
            let ips = Array(Set(conns.map { $0.remoteAddress }))
            let geo = await GeoIP.shared.locate(ips)
            for i in conns.indices {
                if let g = geo[conns[i].remoteAddress] {
                    conns[i].lat = g.lat
                    conns[i].lon = g.lon
                    conns[i].city = g.city
                    conns[i].country = g.country
                }
            }
            await MainActor.run { self.connections = conns }
        }
    }

    func openInBlip(_ c: Connection) {
        if blipInstalled {
            var comps = URLComponents()
            comps.scheme = "blip"
            comps.host = "connection"
            comps.queryItems = [
                .init(name: "proto", value: c.proto),
                .init(name: "raddr", value: c.remoteAddress),
                .init(name: "rport", value: String(c.remotePort)),
                .init(name: "laddr", value: c.localAddress),
                .init(name: "lport", value: String(c.localPort)),
                .init(name: "pid", value: String(c.pid)),
                .init(name: "process", value: c.process),
            ]
            if let url = comps.url {
                NSWorkspace.shared.open(url)
                return
            }
        }
        NSWorkspace.shared.open(PortStore.blipSiteURL)
    }

    func refresh() {
        Task.detached {
            let scanned = PortScanner.scan()
            await MainActor.run { self.ports = scanned }
        }
    }

    func kill(_ p: OpenPort, force: Bool = false) {
        do {
            try ProcessControl.terminate(p.pid, force: force)
            ports.removeAll { $0.pid == p.pid }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func togglePause(_ p: OpenPort) {
        do {
            if pausedPIDs.contains(p.pid) {
                try ProcessControl.resume(p.pid)
                pausedPIDs.remove(p.pid)
            } else {
                try ProcessControl.pause(p.pid)
                pausedPIDs.insert(p.pid)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startForward(listenHost: String, listenPort: UInt16, targetHost: String, targetPort: UInt16) {
        do {
            let id = try forwarder.start(
                listenHost: listenHost,
                listenPort: listenPort,
                targetHost: targetHost,
                targetPort: targetPort
            )
            if !forwards.contains(where: { $0.id == id }) {
                forwards.append(
                    ActiveForward(
                        id: id,
                        listenHost: listenHost,
                        listenPort: listenPort,
                        targetHost: targetHost,
                        targetPort: targetPort
                    )
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopForward(_ id: String) {
        forwarder.stop(id)
        forwards.removeAll { $0.id == id }
    }
}
