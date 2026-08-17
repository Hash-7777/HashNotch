import SwiftUI
import HashNotchKit

/// Compact up/down throughput readout in a fixed MB/s layout.
///
/// Every element has a reserved width and the digits are monospaced, so the
/// arrows, numbers, and unit never shift as the values change — the readout
/// stays rock-steady in place. The style controls which directions appear.
struct NetworkView: View {
    @ObservedObject var monitor: NetworkMonitor
    let theme: Theme
    let style: NetworkStyle

    // Reserved widths keep the layout from reflowing as numbers change.
    private let valueWidth: CGFloat = 52
    private let unitWidth: CGFloat = 34
    private let iconWidth: CGFloat = 12

    var body: some View {
        Group {
            switch style {
            case .stacked:
                // Both numbers in the width of one, which is the whole point of
                // it — the notch has more height to spare than width.
                VStack(alignment: .trailing, spacing: 0) {
                    stackedLine(monitor.uploadBytesPerSec, theme.upColor)
                    stackedLine(monitor.downloadBytesPerSec, theme.downColor)
                }
            case .compact:
                // No arrows, one line. Up first, down second, the way every
                // speed readout on this platform orders them.
                HStack(spacing: 5) {
                    compactValue(monitor.uploadBytesPerSec)
                    Text("·").foregroundStyle(theme.subtitleColor)
                    compactValue(monitor.downloadBytesPerSec)
                    Text(Formatters.megabytesUnit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.subtitleColor)
                }
            case .graph, .both, .downloadOnly, .uploadOnly:
                arrowed
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
        .fixedSize()
    }

    /// The original arrangement: an arrow, a number and a unit per direction.
    private var arrowed: some View {
        HStack(spacing: 16) {
            if style != .downloadOnly {
                metric(systemImage: "arrow.up", rate: monitor.uploadBytesPerSec, color: theme.upColor)
            }
            if style != .uploadOnly {
                metric(systemImage: "arrow.down", rate: monitor.downloadBytesPerSec, color: theme.downColor)
            }
        }
    }

    /// One line of the stacked form: a small tinted triangle and the figure.
    private func stackedLine(_ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(Formatters.megabytesPerSecond(rate))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: rate)
        }
    }

    private func compactValue(_ rate: Double) -> some View {
        Text(Formatters.megabytesPerSecond(rate))
            .foregroundStyle(theme.textColor)
            .monospacedDigit()
            .rollingDigits()
            .animation(.snappy, value: rate)
    }

    private func metric(systemImage: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: iconWidth, alignment: .center)
            Text(Formatters.megabytesPerSecond(rate))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: rate)
                .frame(width: valueWidth, alignment: .trailing)
            Text(Formatters.megabytesUnit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.subtitleColor)
                .frame(width: unitWidth, alignment: .leading)
        }
    }
}

/// Expanded detail: internet speed as a clean row that matches the panel.
struct NetworkDetailView: View {
    @ObservedObject var monitor: NetworkMonitor
    let theme: Theme
    let style: NetworkStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row
            if style == .graph {
                ZStack {
                    Sparkline(values: scaled(monitor.upHistory), tint: theme.upColor)
                    Sparkline(values: scaled(monitor.downHistory), tint: theme.downColor)
                }
                .frame(width: Panel.rowWidth, height: 26)
            }
        }
    }

    private var row: some View {
        NotchRow("Internet", theme: theme) {
            switch style {
            case .stacked:
                VStack(alignment: .trailing, spacing: 1) {
                    speed("arrow.up", monitor.uploadBytesPerSec, theme.upColor)
                    speed("arrow.down", monitor.downloadBytesPerSec, theme.downColor)
                }
            case .compact:
                HStack(spacing: 5) {
                    Text(Formatters.megabytesPerSecond(monitor.uploadBytesPerSec))
                        .foregroundStyle(theme.textColor).monospacedDigit()
                    Text("·").foregroundStyle(theme.subtitleColor)
                    Text(Formatters.megabytesPerSecond(monitor.downloadBytesPerSec))
                        .foregroundStyle(theme.textColor).monospacedDigit()
                    Text("MB/s")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.subtitleColor)
                }
            case .downloadOnly:
                speed("arrow.down", monitor.downloadBytesPerSec, theme.downColor)
            case .uploadOnly:
                speed("arrow.up", monitor.uploadBytesPerSec, theme.upColor)
            case .graph:
                // The numbers keep their row exactly as they are, and the graph
                // goes underneath. Putting the graph where the figures were
                // traded a reading you can act on for a shape you cannot — the
                // shape is context for the numbers, not a replacement.
                HStack(spacing: 12) {
                    speed("arrow.up", monitor.uploadBytesPerSec, theme.upColor)
                    speed("arrow.down", monitor.downloadBytesPerSec, theme.downColor)
                }
            case .both:
                HStack(spacing: 12) {
                    speed("arrow.up", monitor.uploadBytesPerSec, theme.upColor)
                    speed("arrow.down", monitor.downloadBytesPerSec, theme.downColor)
                }
            }
        }
    }

    /// Both lines share one scale, so their heights can be compared. Scaling
    /// each to its own peak would draw a trickle and a torrent identically.
    private func scaled(_ values: [Double]) -> [Double] {
        let ceiling = monitor.graphCeiling
        return values.map { ceiling > 0 ? $0 / ceiling : 0 }
    }

    private func speed(_ symbol: String, _ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(Formatters.megabytesPerSecond(rate))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: rate)
            Text("MB/s")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.subtitleColor)
        }
    }
}
