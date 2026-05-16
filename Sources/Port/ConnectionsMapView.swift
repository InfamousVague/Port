import SwiftUI
import MapKit

struct ConnectionsMapView: View {
    @Environment(PortStore.self) private var store
    @State private var camera: MapCameraPosition = .automatic

    private var located: [Connection] {
        store.connections.filter { $0.isLocatable }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            footerBar
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.connections.isEmpty {
            placeholder("Scanning active connections…")
        } else if located.isEmpty {
            placeholder("\(store.connections.count) connection(s) — none geolocated yet")
        } else {
            Map(position: $camera) {
                ForEach(located) { connection in
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: connection.lat ?? 0,
                            longitude: connection.lon ?? 0
                        )
                    ) {
                        ConnectionPin(connection: connection) {
                            store.openInBlip(connection)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onAppear { fit() }
            .onChange(of: located.count) { fit() }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            Text("\(located.count) located · \(store.connections.count) total")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(store.blipInstalled ? "tap a dot → open in Blip" : "tap a dot → get Blip")
                .font(.system(size: 10))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fit() {
        let pts = located.compactMap { c -> CLLocationCoordinate2D? in
            guard let la = c.lat, let lo = c.lon else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }
        guard !pts.isEmpty else { return }
        let lats = pts.map(\.latitude)
        let lons = pts.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: Swift.max((maxLat - minLat) * 1.4, 8),
            longitudeDelta: Swift.max((maxLon - minLon) * 1.4, 8)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct ConnectionPin: View {
    let connection: Connection
    let onTap: () -> Void

    private var helpText: String {
        var s = "\(connection.process) → \(connection.remoteAddress):\(connection.remotePort)"
        if let city = connection.city { s += "  ·  \(city)" }
        if let country = connection.country { s += ", \(country)" }
        return s
    }

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
