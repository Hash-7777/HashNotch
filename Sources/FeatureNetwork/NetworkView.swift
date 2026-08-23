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
            byApp
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
                // Whatever has to be admitted about these figures is admitted
                // HERE, as a mark beside them, rather than as a line of small
                // print underneath.
                //
                // It used to be that line. It was honest and it was in the
                // wrong place: it turned a one-line readout into a two-line
                // one, and it did so exactly when the numbers were long, so
                // the row changed shape as the day went on. A panel row is
                // read at a glance and its height should not depend on how
                // much data somebody has used.
                //
                // A mark is still an admission — it is visible, it is beside
                // the figure it qualifies, and it is not the ordinary state of
                // the row — and the sentence is one hover away rather than
                // gone. Nothing is quietly dropped: every case that produced a
                // line produces a mark.
                if let note = caption {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.subtitleColor)
                        .help(note)
                }
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
    }

    /// Which programs the traffic went through: the two that used the most,
    /// under the total they add up towards.
    ///
    /// Under it rather than beside it, and named rather than merely counted,
    /// because "nine gigabytes today" is a fact you can do nothing with and
    /// "eight of them were one program" is a fact you can. Two, so the row
    /// stays a footnote to the total instead of becoming a second list.
    @ViewBuilder
    private var byApp: some View {
        ForEach(monitor.topApps, id: \.name) { app in
            NotchRow(app.name, theme: theme) {
                HStack(spacing: 12) {
                    amount("arrow.down", app.received, theme.downColor)
                    amount("arrow.up", app.sent, theme.upColor)
                }
            }
            // Quieter than the total above it. These explain that figure, and
            // a breakdown drawn as loudly as the thing it breaks down competes
            // with it for the glance.
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .opacity(0.82)
        }
    }

    /// What has to be admitted about the figures, or nothing when they are
    /// whole.
    ///
    /// Two different admissions, and they are not the same sentence: the count
    /// started late, or there is a hole in the middle of it. Both used to be
    /// three or four words of small print, which was short enough to fit and
    /// too short to mean anything — "some time not counted" says that
    /// something is missing without saying what, when, or why, which invites
    /// the worst reading available. They now say the whole thing, because a
    /// mark you hover has room for a sentence where a line under the row did
    /// not.
    private var caption: String? {
        if !monitor.usage.coversWholeSpan, let since = monitor.usage.countedSince {
            return """
                This figure starts at \(Self.sinceText(since)), not at the \
                beginning of \(period.caption). HashNotch counts from the \
                moment it is running, and it was not running for the whole of \
                this span — so the real number is higher than the one shown.
                """
        }
        if monitor.usage.missedTime {
            return """
                HashNotch was closed across a change of day during \
                \(period.caption), and what went through while it was closed \
                is not counted here. Your Mac's counters keep running, but \
                they do not record WHEN — so those bytes could not be put \
                against any one day, and were left out rather than guessed at. \
                The real number is higher than the one shown.
                """
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
