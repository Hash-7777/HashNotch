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
    let period: NetworkUsagePeriod

    var body: some View {
        // Speed, then the shape of the last half-minute, then the total. The
        // graph belongs directly under the numbers it is a picture of; the
        // total is a different question and reads as an answer to the graph if
        // it is put between them.
        VStack(alignment: .leading, spacing: 5) {
            row
            if style == .graph {
                ZStack {
                    Sparkline(values: scaled(monitor.upHistory), tint: theme.upColor)
                    Sparkline(values: scaled(monitor.downHistory), tint: theme.downColor)
                }
                .frame(width: Panel.rowWidth, height: 26)
            }
            used
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

    /// How much has gone through, over the span the settings ask for.
    ///
    /// A second row rather than a second pair of numbers in the first one:
    /// speed and total are different questions — what is happening now, and
    /// what has happened — and a row that answered both at once would have to
    /// be read twice to answer either.
    private var used: some View {
        NotchRow("Used \(period.caption)", theme: theme) {
            HStack(spacing: 12) {
                amount("arrow.down", monitor.usage.received, theme.downColor)
                amount("arrow.up", monitor.usage.sent, theme.upColor)
                // Only where it means something. A span counted from the
                // beginning of a day or a month starts itself; this one is the
                // one that has to be started by hand, and the button belongs
                // beside the figure it clears rather than in a settings window
                // two clicks away from it.
                if period == .sinceReset {
                    Button {
                        monitor.resetUsage()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.subtitleColor)
                    }
                    .buttonStyle(.plain)
                    .help("Start counting again from now")
                }
            }
        }
        // Said, rather than left to be assumed, whenever the figures cover less
        // than the span they are named after. Two different admissions, and
        // they are not the same sentence: the count started late (the first day
        // of use, or a month that began before the app was installed), or there
        // is a hole in the middle of it (the app was closed across days, and
        // what went through in between belongs to no day in particular).
        .overlay(alignment: .bottomLeading) {
            if let note = caption {
                Text(note)
                    .font(.system(size: 8))
                    .foregroundStyle(theme.subtitleColor)
                    .offset(y: 9)
            }
        }
        .padding(.bottom, caption == nil ? 0 : 10)
    }

    /// What to admit under the figures, or nothing when they are whole.
    private var caption: String? {
        if !monitor.usage.coversWholeSpan, let since = monitor.usage.countedSince {
            return "counted since \(Self.sinceText(since))"
        }
        if monitor.usage.missedTime {
            return "some time not counted"
        }
        return nil
    }

    /// The day for anything older than today, the time for today itself —
    /// "counted since 09:12" reads as this morning, where a date would leave
    /// somebody working out whether it means this morning.
    private static func sinceText(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }

    private func amount(_ symbol: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(Formatters.bytes(Int64(clamping: bytes)))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: bytes)
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
