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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotchSectionHeader("AI TOKENS", theme: theme)
            row("Total AI tokens", monitor.today.total, emphasized: true)
            // "Number only" is a request for the number. The per-tool breakdown
            // is the part someone choosing that style is asking not to see.
            if style == .labeled {
                row("Claude Code", monitor.today.claude)
                if monitor.today.hashCortx > 0 { row("HashCortx", monitor.today.hashCortx) }
                if monitor.today.hashCerebrum > 0 { row("HashCerebrum", monitor.today.hashCerebrum) }
            }
            if style == .labeled, monitor.today.cached > 0 {
                NotchRow("Cached", theme: theme) {
                    Text("+\(Formatters.compactCount(monitor.today.cached))")
                        .foregroundStyle(theme.subtitleColor)
                        .monospacedDigit()
                }
            }
            freshness
        }
    }

    /// When the count was taken, and a way to take it again.
    ///
    /// The number is not live — it is counted on a schedule the reader chooses,
    /// and can be set to no schedule at all. A figure that might be an hour old
    /// with nothing saying so is a figure that quietly misleads, so it says.
    private var freshness: some View {
        HStack(spacing: 6) {
            Text(freshnessText)
                .font(.system(size: 9))
                .foregroundStyle(theme.subtitleColor)
            Spacer(minLength: 8)
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
        .frame(width: Panel.rowWidth)
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
