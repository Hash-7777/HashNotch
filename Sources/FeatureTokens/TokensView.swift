import SwiftUI
import HashNotchKit

/// Compact token readout: today's total AI tokens across your tools.

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
    /// an hour old with nothing saying so is a figure that quietly misleads.
    /// The per-tool breakdown went to the tooltip: it is an answer to "where
    /// did that come from", which is a question somebody asks deliberately, and
    /// it was costing three lines to answer before it was asked.
    ///
    /// The mark is drawn larger than the row's own text because it is now the
    /// only thing naming this section — there is no heading above it any more,
    /// so the picture has to do the work the heading used to.
    var body: some View {
        NotchRow("AI tokens", icon: .tokens, iconSize: 13, theme: theme) {
            HStack(spacing: 6) {
                // "Number only" is a request for the number, and the age is the
                // one thing on this row that can be given up without giving up
                // something true — it moves to the tooltip rather than being
                // dropped, so a count that might be an hour old still says so
                // to anybody who asks it.
                //
                // Collapsing this section to one line took its setting with it
                // by accident: the row was rewritten and stopped consulting the
                // choice at all, so picking either option in Settings did
                // nothing. That is the failure this branch undoes.
                if style == .labeled {
                    Text(freshnessText)
                        .font(.system(size: 8.5))
                        .foregroundStyle(theme.subtitleColor)
                        .lineLimit(1)
                }
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
        .help(tooltip)
        .animation(.snappy, value: monitor.today.total)
    }

    /// What the row says when asked rather than at a glance: where the figure
    /// came from, and — when the row is set to the number alone — how old it is.
    private var tooltip: String {
        style == .labeled ? breakdown : "\(freshnessText)\n\(breakdown)"
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
        TokenFreshness.text(
            countedAt: monitor.countedAt,
            isCounting: monitor.isCounting,
            now: Date()
        )
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
