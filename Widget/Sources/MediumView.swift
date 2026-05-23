import SwiftUI
import WidgetKit
import PortShared

/// `.systemMedium`: hero count on the left, top-3 process rollup
/// on the right, refresh pill bottom-left.
struct MediumView: View {
    let entry: PortEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PORT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text("\(entry.state.totalCount)")
                    .font(.system(size: 32, weight: .heavy,
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
                // text. Replaces the hand-rolled blue capsule that
                // was illegible in the dimmed widget state.
                Button(intent: RefreshPortIntent()) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TOP")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                if entry.state.topProcesses.isEmpty {
                    Text(entry.state.totalCount == 0
                         ? "no ports open" : "no top rollup yet")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(entry.state.topProcesses.prefix(3),
                            id: \.name) { row in
                        HStack(alignment: .firstTextBaseline,
                               spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text("\(row.portCount)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}
