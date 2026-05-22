import SwiftUI
import WidgetKit
import PortShared

/// `.systemSmall` Port layout: brand tag, big total-count number,
/// TCP/UDP split subline, and a Refresh pill at the bottom.
struct SmallView: View {
    let entry: PortEntry

    // Hardcoded blue (#0099ff range). Color.accentColor was
    // resolving to white on the desktop widget surface in earlier
    // Alfred testing, washing the pill into invisibility.
    private let portBlue = Color(red: 0.36, green: 0.72, blue: 1.00)

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

            Button(intent: RefreshPortIntent()) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(portBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(12)
    }
}
