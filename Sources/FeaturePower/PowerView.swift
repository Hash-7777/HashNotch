import SwiftUI
import HashNotchKit

/// The panel row: the whole Mac's draw, with the last minute graphed under it,
/// in the same arrangement as the processor readout.
struct PowerDetailView: View {
    @ObservedObject var monitor: PowerMonitor
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            NotchRow("Power", icon: .power, theme: theme) {
                Text(monitor.watts.map(PowerFormat.watts) ?? "—")
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .rollingDigits()
            }
            .help(helpText)
            Sparkline(
                values: PowerScale.normalised(monitor.history, chargerWatts: monitor.chargerWatts),
                tint: tint,
                // The dashed limit line only where there is a limit: the
                // charger's rating. On battery it would be a line at nothing.
                showsScale: monitor.chargerWatts != nil
            )
            .frame(width: Panel.rowWidth, height: 26)
        }
        .animation(.snappy, value: monitor.watts)
    }

    private var tint: Color {
        theme.color(for: PowerLevel.level(watts: monitor.watts ?? 0, chargerWatts: monitor.chargerWatts))
    }

    private var helpText: String {
        if let charger = monitor.chargerWatts {
            return "What the whole Mac is using right now. The line at the top of the graph is your \(Int(charger)) W charger's limit."
        }
        return "What the whole Mac is using right now, from the battery."
    }
}
