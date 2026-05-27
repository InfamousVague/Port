import Foundation
import Observation
import AppKit
import SuiteKit
import PortShared

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
    /// "proto:port" the user asked to jump to (set from a notification click).
    var focusedPortKey: String?
    /// "proto:port" -> user label. Trusted ports don't notify on (re)appear.
    var trusted: [String: String] = [:]

    @ObservationIgnored private var seenPortKeys: Set<String> = []
    @ObservationIgnored private var firstScanDone = false
    @ObservationIgnored private let trustDefaultsKey = "trustedPorts.v1"

    // Halo live-activity fade state. Port writes its pill
    // only when the count just changed, then schedules a
    // clear so the slot frees up after `haloFadeDelay` —
    // pinning the pill permanently turned the island into a
    // boring "you have 12 open ports" reminder rather than a
    // transient ping when something opened or closed.
    @ObservationIgnored private var lastPublishedCount: Int?
    @ObservationIgnored private var haloFadeTimer: Timer?
    @ObservationIgnored private let haloFadeDelay: TimeInterval = 5

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
        loadTrust()
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
        // Halo's expanded-card "kill" button posts the pid as
        // a String — listen and call through to the same
        // `killByPid` path so the popover UI and the island
        // share one terminate flow.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(
                "com.mattssoftware.port.kill"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let pidString = note.object as? String,
                  let pid = Int32(pidString) else { return }
            Task { @MainActor in
                self?.killByPid(pid)
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
            await MainActor.run { self.applyScan(scanned) }
        }
    }

    private func applyScan(_ scanned: [OpenPort]) {
        ports = scanned
        let current = Set(scanned.map { "\($0.proto):\($0.port)" })
        if firstScanDone {
            // Trusted ports are vetted by the user — never notify on them.
            let newKeys = current.subtracting(seenPortKeys)
                .filter { trusted[$0] == nil }
            if newKeys.count > 5 {
                Notifier.postSummary(count: newKeys.count)
            } else {
                for p in scanned where newKeys.contains("\(p.proto):\(p.port)") {
                    Notifier.postNewPort(
                        key: "\(p.proto):\(p.port)",
                        port: p.port,
                        proto: p.proto,
                        process: p.process,
                        service: KnownPorts.name(p.port)
                    )
                }
            }
        }
        seenPortKeys = current
        firstScanDone = true
        publishSharedSnapshot()
        publishLiveActivity()
    }

    /// Surface Port's state in the system-wide island (Halo)
    /// as a **transient ping**: write the pill only when the
    /// listening-port count just changed, then schedule a
    /// `haloFadeDelay`-second clear so the slot disappears
    /// instead of camping there forever. Restarts the fade
    /// timer on every fresh change (rapid open/close churn
    /// extends visibility until things settle).
    ///
    /// Priority 30 keeps the pill well below transient HUDs
    /// and Espresso's countdown when other activities are
    /// competing for the slot.
    private func publishLiveActivity() {
        let count = ports.count
        if count == 0 {
            SuiteLiveActivityStore.clear("port")
            lastPublishedCount = 0
            haloFadeTimer?.invalidate()
            haloFadeTimer = nil
            return
        }
        // No change since the last publish → leave whatever
        // we wrote alone (it's either still on screen if the
        // fade timer hasn't fired yet, or already gone).
        guard count != lastPublishedCount else { return }
        lastPublishedCount = count
        // `sailboat.fill` matches the SF Symbol Port already
        // uses for its menu-bar item (`PortBrand.menuBarIcon`),
        // so the island pill and the status item read as the
        // same app at a glance.
        //
        // Surface the top few listening ports too so Halo's
        // expanded card can render rows with per-row kill
        // buttons. Sort by port number (well-known ports rise
        // to the top, where they're usually the ones the user
        // wants to act on first), cap at 6 so the dropdown
        // fills its 2×3 grid exactly. More than 6 would push
        // a fourth grid row past the comfortable expanded
        // height; fewer leaves an empty cell.
        let topEntries = ports
            .sorted { $0.port < $1.port }
            .prefix(6)
            .map { p in
                SuiteLiveActivityStore.PortEntry(
                    proto: p.proto,
                    port: p.port,
                    pid: p.pid,
                    process: p.process,
                    service: KnownPorts.name(p.port))
            }
        let payload = SuiteLiveActivityStore.Payload(
            compactLeadingSymbol: "sailboat.fill",
            compactTrailingText: "\(count)",
            tintHex: "#2E9BD6",
            priority: 30,
            port: SuiteLiveActivityStore.PortData(
                entries: Array(topEntries)))
        try? SuiteLiveActivityStore.write(payload, for: "port")
        // Bounce the fade timer — give the pill a fresh
        // window after each change so a flurry of opens /
        // closes keeps it visible until the dust settles.
        haloFadeTimer?.invalidate()
        haloFadeTimer = Timer.scheduledTimer(
            withTimeInterval: haloFadeDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                SuiteLiveActivityStore.clear("port")
                self.haloFadeTimer = nil
            }
        }
    }

    /// Publish a compact snapshot for the widget extension to read.
    /// SharedPortStore writes the JSON to the Group Container and
    /// kicks WidgetKit to reload its timeline.
    private func publishSharedSnapshot() {
        // Top processes by listening-port count.
        var byProcess: [String: Int] = [:]
        for p in ports {
            byProcess[p.process, default: 0] += 1
        }
        let top = byProcess.sorted { $0.value > $1.value }
            .prefix(3)
            .map { SharedPort.ProcessRow(
                name: $0.key, portCount: $0.value) }
        let tcp = ports.filter { $0.proto == "tcp" }.count
        let udp = ports.filter { $0.proto == "udp" }.count
        let snapshot = SharedPort(
            totalCount: ports.count,
            tcpCount: tcp,
            udpCount: udp,
            topProcesses: Array(top),
            sampledAt: Date()
        )
        SharedPortStore.write(snapshot)
    }

    // MARK: - Trust

    func setTrust(key: String, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        trusted[key] = trimmed.isEmpty ? "Trusted" : trimmed
        persistTrust()
    }

    func untrust(key: String) {
        trusted.removeValue(forKey: key)
        persistTrust()
    }

    private func loadTrust() {
        guard let data = UserDefaults.standard.data(forKey: trustDefaultsKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        trusted = map
    }

    private func persistTrust() {
        if let data = try? JSONEncoder().encode(trusted) {
            UserDefaults.standard.set(data, forKey: trustDefaultsKey)
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

    /// Halo's expanded-card "kill" button posts the pid; we
    /// look it up in the current ports list and reuse the
    /// existing kill path so the popover and the island stay
    /// in step (same error surface, same removal animation).
    /// No-op if the pid is no longer listening — the row in
    /// Halo is stale and will refresh on the next publish.
    func killByPid(_ pid: Int32, force: Bool = false) {
        guard let p = ports.first(where: { $0.pid == pid })
        else { return }
        kill(p, force: force)
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
