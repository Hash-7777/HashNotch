import SwiftUI
import HashNotchKit

/// Expanded detail: AirPods battery as clean rows that match the panel — Left,
/// Right, and Case while a pair is connected; nothing when it isn't.
struct AirPodsDetailView: View {
    @ObservedObject var monitor: AirPodsMonitor
    let theme: Theme

    var body: some View {
        if let battery = monitor.battery, !battery.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                NotchSectionHeader("AIRPODS", theme: theme)
                if let single = battery.single, battery.left == nil, battery.right == nil {
                    row("AirPods", single)
                } else {
                    if let left = battery.left { row("Left", left) }
                    if let right = battery.right { row("Right", right) }
                }
                if let caseLevel = battery.caseLevel { row("Case", caseLevel) }
            }
        }
    }

    private func row(_ label: String, _ percent: Int) -> some View {
        NotchRow(label, theme: theme) {
            HStack(spacing: 5) {
                Image(systemName: symbol(for: percent))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(percent <= 20 ? theme.upColor : theme.downColor)
                Text("\(percent)%")
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
            }
        }
        .animation(.snappy, value: percent)
    }

    /// A battery glyph that fills with the level, like the iPhone. Uses the same
    /// short SF Symbol names the Mac battery readout uses.
    private func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
