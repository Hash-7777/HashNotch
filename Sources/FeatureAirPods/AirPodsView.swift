import SwiftUI
import HashNotchKit

/// Expanded detail: AirPods battery as one row — L, R and Case side by side
/// while a pair is connected; nothing when it isn't. See `AirPodsSummary`.
struct AirPodsDetailView: View {
    @ObservedObject var monitor: AirPodsMonitor
    let theme: Theme

    var body: some View {
        if let battery = monitor.battery, !battery.isEmpty {
            NotchRow("AirPods", icon: .airpods, theme: theme) {
                HStack(spacing: 10) {
                    ForEach(AirPodsSummary.items(for: battery), id: \.label) { item in
                        HStack(spacing: 3) {
                            if !item.label.isEmpty {
                                Text(item.label)
                                    .foregroundStyle(theme.subtitleColor)
                            }
                            Text("\(item.percent)%")
                                .foregroundStyle(AirPodsSummary.isLow(item.percent) ? Theme.danger : theme.textColor)
                                .monospacedDigit()
                                .rollingDigits()
                        }
                        .animation(.snappy, value: item.percent)
                    }
                }
            }
        }
    }
}
