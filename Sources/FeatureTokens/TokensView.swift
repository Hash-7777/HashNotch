import SwiftUI
import HashNotchKit

/// Compact token readout: today's total AI tokens across your tools.
struct TokensView: View {
    @ObservedObject var monitor: TokensMonitor
    let theme: Theme
    let style: TokensStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(Formatters.compactCount(monitor.today.total))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
            if style == .labeled {
                Text("today")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(theme.pillBackground))
        .animation(.snappy, value: monitor.today.total)
    }
}

/// Expanded detail: today's tokens broken down by source.
struct TokensDetailView: View {
    @ObservedObject var monitor: TokensMonitor
    let theme: Theme
    let style: TokensStyle

    /// One line, and everything that used to be four.
    ///
    /// It was a heading, a total, a row per tool and a line saying when the
    /// count was taken — five lines of panel for one number, in a panel whose
    /// height is the scarcest thing it has. It is now a single row: the mark,
    /// the name, how old the figure is, the figure, and the button that counts
    /// again.
    ///
    /// Nothing that was TRUE has been dropped, only spread out less. How old
    /// the count is stays on the row, in words, because a figure that might be
    /// an hour old with nothing saying so is a figure that quietly misleads —
    /// it is the one thing here that could not go to a tooltip. The per-tool
    /// breakdown did go to one: it is an answer to "where did that come from",
    /// which is a question somebody asks deliberately, and it was costing three
    /// lines to answer before it was asked.
    ///
    /// The mark is drawn larger than the row's own text because it is now the
    /// only thing naming this section — there is no heading above it any more,
    /// so the picture has to do the work the heading used to.
    var body: some View {
        NotchRow("AI tokens", icon: .tokens, iconSize: 13, theme: theme) {
            HStack(spacing: 6) {
                Text(freshnessText)
                    .font(.system(size: 8.5))
                    .foregroundStyle(theme.subtitleColor)
                    .lineLimit(1)
                Text(Formatters.compactCount(monitor.today.total))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
                    .layoutPriority(1)
                Button(action: { monitor.refreshNow() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(monitor.isCounting ? theme.accent : theme.subtitleColor)
                        .rotationEffect(.degrees(monitor.isCounting ? 360 : 0))
                        .animation(
                            monitor.isCounting
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: monitor.isCounting
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(monitor.isCounting)
                .help("Count again now")
            }
        }
        .help(breakdown)
        .animation(.snappy, value: monitor.today.total)
    }

    /// Where the figure came from, for somebody who asks.
    ///
    /// Only the sources that actually contributed. A tool nobody uses listed at
    /// zero is a row that says "this app expected something of you".
    private var breakdown: String {
        var lines: [String] = []
        if monitor.today.claude > 0 {
            lines.append("Claude Code: \(Formatters.compactCount(monitor.today.claude))")
        }
        if monitor.today.hashCortx > 0 {
            lines.append("HashCortx: \(Formatters.compactCount(monitor.today.hashCortx))")
        }
        if monitor.today.hashCerebrum > 0 {
            lines.append("HashCerebrum: \(Formatters.compactCount(monitor.today.hashCerebrum))")
        }
        if monitor.today.cached > 0 {
            lines.append("Cached: +\(Formatters.compactCount(monitor.today.cached))")
        }
        return lines.isEmpty ? "Nothing counted yet today" : lines.joined(separator: "\n")
    }

    private var freshnessText: String {
        guard let countedAt = monitor.countedAt else { return "not counted yet" }
        if monitor.isCounting { return "counting…" }
        let seconds = Int(Date().timeIntervalSince(countedAt))
        if seconds < 60 { return "counted just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "counted \(minutes) min ago" }
        return "counted \(minutes / 60)h ago"
    }

    private func row(_ label: String, _ value: Int64, emphasized: Bool = false) -> some View {
        NotchRow(label, emphasized: emphasized, theme: theme) {
            // `.fontWeight` on a Text is macOS 13; setting the weight through
            // the font itself is not, and produces the same result. The row's
            // size is fixed by the panel, so the font is stated in full here
            // rather than inherited.
            Text(Formatters.compactCount(value))
                .font(.system(size: 11, weight: emphasized ? .bold : .regular, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
        }
        .animation(.snappy, value: value)
    }
}
