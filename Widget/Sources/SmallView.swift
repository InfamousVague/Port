import SwiftUI
import WidgetKit
import PortShared

/// `.systemSmall` Port layout: brand tag, big total-count number,
/// TCP/UDP split subline, and a Refresh pill at the bottom.
struct SmallView: View {
    let entry: PortEntry

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            Text("PORT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Text("\(entry.state.totalCount)")
                .font(.system(size: 36, weight: .heavy,
                              design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(entry.state.totalCount == 1
                 ? "open port" : "open ports")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if entry.state.totalCount > 0 {
                Text("\(entry.state.tcpCount) TCP · "
                     + "\(entry.state.udpCount) UDP")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // System `.bordered` — translucent gray pill, primary
            // text. Was a hand-rolled blue capsule with explicit
            // white text; that combo broke in the dimmed widget
            // state on macOS Tahoe (system desaturates the blue to
            // near-white, leaves the white text alone → illegible
            // white-on-white). System bordered style stays legible
            // across focus states and matches the family aesthetic.
            Button(intent: RefreshPortIntent()) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(12)
    }
}
