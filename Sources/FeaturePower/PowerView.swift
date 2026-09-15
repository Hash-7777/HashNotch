import SwiftUI
import HashNotchKit

/// The panel row: what the whole Mac is using right now, as one figure.
struct PowerDetailView: View {
    @ObservedObject var monitor: PowerMonitor
    let theme: Theme

    var body: some View {
        NotchRow("Power consumption", icon: .power, theme: theme) {
            Text(monitor.watts.map(PowerFormat.watts) ?? "—")
                .foregroundStyle(tint)
                .monospacedDigit()
                .rollingDigits()
        }
        .help(helpText)
        .animation(.snappy, value: monitor.watts)
    }

    private var tint: Color {
        theme.color(for: PowerLevel.level(watts: monitor.watts ?? 0, chargerWatts: monitor.chargerWatts))
    }

    private var helpText: String {
        if let charger = monitor.chargerWatts {
            return "What the whole Mac is using right now. It turns red at 90% of what your \(Int(charger)) W charger can give."
        }
        return "What the whole Mac is using right now, from the battery."
    }
}
