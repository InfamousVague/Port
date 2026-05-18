import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PortStore.self) private var store
    @State private var forwardTarget: OpenPort?

    var body: some View {
        VStack(spacing: 0) {
            header
            mapCard
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 598)
        .sheet(item: $forwardTarget) { port in
            ForwardSheet(source: port) { lh, lp, th, tp, mapExternally, extPort in
                store.startForward(listenHost: lh, listenPort: lp, targetHost: th, targetPort: tp)
                if mapExternally {
                    Task { await store.mapExternal(proto: .tcp, internalPort: lp, externalPort: extPort) }
                }
                forwardTarget = nil
            } onCancel: {
                forwardTarget = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center, spacing: 6) {
                Image(nsImage: PortApp.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text("PORT")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                LiveDot()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(store.hostname)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("LAN \(store.primaryIP)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tint)
                if let ext = store.externalIP {
                    Text("WAN \(ext)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var mapCard: some View {
        ConnectionsMapView()
            .frame(height: 188)
            .background(Color.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if !store.forwards.isEmpty {
                    forwardsStrip
                }
                if !store.mappings.isEmpty {
                    mappingsStrip
                }
                if store.ports.isEmpty {
                    Text("No listening ports found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.ports.enumerated()), id: \.element.id) { index, port in
                            let key = "\(port.proto):\(port.port)"
                            PortRow(
                                port: port,
                                paused: store.pausedPIDs.contains(port.pid),
                                highlighted: store.focusedPortKey == key,
                                trustedLabel: store.trusted[key],
                                onKill: { confirmKill(port) },
                                onPause: { store.togglePause(port) },
                                onForward: { forwardTarget = port },
                                onTrust: { promptTrust(port, key: key) },
                                onUntrust: { store.untrust(key: key) }
                            )
                            .id(key)
                            if index < store.ports.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .glassScrollers()
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: store.focusedPortKey) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if store.focusedPortKey == key { store.focusedPortKey = nil }
                }
            }
        }
    }

    private var forwardsStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.forwards) { f in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tint)
                    Text(f.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.stopForward(f.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var mappingsStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.mappings) { m in
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 9))
                        .foregroundStyle(.tint)
                    Text("router \(m.proto):\(m.externalPort) → :\(m.internalPort)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await store.unmapExternal(m) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Quit Port") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func confirmKill(_ port: OpenPort) {
        let alert = NSAlert()
        alert.messageText = "Kill \(port.process)?"
        alert.informativeText = "PID \(port.pid) is holding \(port.proto.uppercased()) port \(port.port). This sends SIGTERM."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.kill(port)
        }
    }

    private func promptTrust(_ port: OpenPort, key: String) {
        let alert = NSAlert()
        alert.messageText = "Trust \(port.proto.uppercased()) port \(port.port)?"
        alert.informativeText = "Trusted ports won't trigger \"new port\" notifications. Give it a label:"
        alert.addButton(withTitle: store.trusted[key] == nil ? "Trust" : "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = store.trusted[key]
            ?? KnownPorts.name(port.port)
            ?? port.process
        field.placeholderString = "e.g. My dev server"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            store.setTrust(key: key, label: field.stringValue)
        }
    }
}

private struct PortRow: View {
    let port: OpenPort
    let paused: Bool
    let highlighted: Bool
    let trustedLabel: String?
    let onKill: () -> Void
    let onPause: () -> Void
    let onForward: () -> Void
    let onTrust: () -> Void
    let onUntrust: () -> Void

    private var service: String? { KnownPorts.name(port.port) }

    var body: some View {
        HStack(spacing: 8) {
            Text(port.proto.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(port.proto == "tcp" ? Color.accentColor : Color.secondary, lineWidth: 1)
                )
                .foregroundStyle(port.proto == "tcp" ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("\(port.address):\(port.port)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    if let service {
                        Text(service)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                    if let trustedLabel {
                        Label(trustedLabel, systemImage: "checkmark.seal.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                }
                Text("\(port.process)  ·  pid \(port.pid)\(paused ? "  ·  paused" : "")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Button("Forward…", action: onForward)
                Button(paused ? "Resume" : "Pause", action: onPause)
                Divider()
                if trustedLabel == nil {
                    Button("Trust This Port…", action: onTrust)
                } else {
                    Button("Edit Trust Label…", action: onTrust)
                    Button("Untrust", action: onUntrust)
                }
                Divider()
                Button("Kill", role: .destructive, action: onKill)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .contentShape(Rectangle())
    }
}

private struct ForwardSheet: View {
    let source: OpenPort
    let onStart: (String, UInt16, String, UInt16, Bool, UInt16) -> Void
    let onCancel: () -> Void

    @State private var listenHost = "127.0.0.1"
    @State private var listenPort: String
    @State private var targetHost = "127.0.0.1"
    @State private var targetPort: String
    @State private var mapExternally = false
    @State private var externalPort: String

    init(source: OpenPort,
         onStart: @escaping (String, UInt16, String, UInt16, Bool, UInt16) -> Void,
         onCancel: @escaping () -> Void) {
        self.source = source
        self.onStart = onStart
        self.onCancel = onCancel
        _listenPort = State(initialValue: String(source.port + 1))
        _targetPort = State(initialValue: String(source.port))
        _externalPort = State(initialValue: String(source.port + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Forward port \(source.port) (\(source.process))")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 10) {
                field("Listen host", text: $listenHost)
                field("Listen port", text: $listenPort)
            }
            HStack(spacing: 10) {
                field("Target host", text: $targetHost)
                field("Target port", text: $targetPort)
            }

            Toggle(isOn: $mapExternally) {
                Text("Also map on router (NAT-PMP)")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            if mapExternally {
                HStack(spacing: 10) {
                    field("External port", text: $externalPort)
                    Spacer()
                }
            }

            Text("Opens a local TCP proxy on Network.framework. Use 0.0.0.0 as listen host to reach it across your LAN. NAT-PMP asks the router to open the external port — works on routers with NAT-PMP/PCP enabled.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Start forward") {
                    guard let lp = UInt16(listenPort), let tp = UInt16(targetPort) else { return }
                    let lh = listenHost.trimmingCharacters(in: .whitespaces)
                    let th = targetHost.trimmingCharacters(in: .whitespaces)
                    let ep = UInt16(externalPort) ?? lp
                    onStart(
                        lh.isEmpty ? "127.0.0.1" : lh, lp,
                        th.isEmpty ? "127.0.0.1" : th, tp,
                        mapExternally, ep
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

private struct LiveDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .help("Live — refreshing every second")
    }
}
