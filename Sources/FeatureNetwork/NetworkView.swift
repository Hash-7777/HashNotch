import SwiftUI
import HashNotchKit

/// Compact up/down throughput readout in a fixed MB/s layout.
///
/// Every element has a reserved width and the digits are monospaced, so the
/// arrows, numbers, and unit never shift as the values change — the readout
/// stays rock-steady in place. The style controls which directions appear.

/// Expanded detail: internet speed as a clean row that matches the panel.
struct NetworkDetailView: View {
    @ObservedObject var monitor: NetworkMonitor
    @ObservedObject var settings: SettingsStore
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
        // Scoped to the one value, rather than wrapped around the change that
        // produces it.
        //
        // The toggle used to sit inside `withAnimation`, which animates every
        // consequence of that transaction — and the value lives on the settings
        // store, which the whole panel and every feature in it observes. One
        // disclosure opening therefore invited unrelated views to animate their
        // own layout at the same time. Naming the value here keeps the motion
        // where it belongs.
        .animation(.snappy(duration: 0.22), value: settings.networkAppsExpanded)
    }

    private var row: some View {
        NotchRow("Internet", icon: .internet, theme: theme) {
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
    /// A block of its own rather than another row, because a total and a speed
    /// are different kinds of thing and drawing them the same way was making
    /// the second one read as a second opinion about the first. See
    /// `NetworkUsedView` for the whole of that reasoning.
    private var used: some View {
        NetworkUsedView(
            received: monitor.usage.received,
            sent: monitor.usage.sent,
            periodCaption: period.caption,
            note: caption,
            onReset: period == .sinceReset ? { monitor.resetUsage() } : nil,
            theme: theme
        )
    }

    /// Which programs the traffic went through: a list that opens and shuts,
    /// under the total it explains.
    ///
    /// It was a flat run of ordinary panel rows, which was the problem. Drawn
    /// like the "Used today" row above them, they read as three more readings
    /// of equal standing rather than as a breakdown OF that one — and there is
    /// no arrangement of the same row that fixes that, because the sameness is
    /// the message. A breakdown has to look subordinate to the thing it breaks
    /// down.
    ///
    /// The total above has since become a block of its own, with a split bar of
    /// the same two colours as these — heavier than these, because it is what
    /// they are a breakdown of.
    ///
    /// So it is a disclosure now: one quiet heading that names the biggest
    /// while shut, and a list of its own kind of row while open. Shut, it costs
    /// a line and still answers "who used the most". Open, it can afford to say
    /// more than two, because somebody who opened it is asking rather than
    /// glancing.
    @ViewBuilder
    private var byApp: some View {
        if !monitor.topApps.isEmpty {
            appsHeading
            if settings.networkAppsExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleApps, id: \.name) { app in
                        NetworkAppRow(
                            app: app,
                            biggest: monitor.topApps.first?.total ?? 0,
                            theme: theme)
                    }
                }
                // A fade, and nothing else.
                //
                // This was a fade combined with a slide from the top edge, on
                // the reasoning that the rows should appear to come out from
                // under the heading. A move transition offsets the block by its
                // own height while the stack around it is simultaneously
                // changing height for the same reason — two motions describing
                // one event, in a container that is itself being resized. What
                // it looks like is rows arriving from the wrong place and
                // overshooting.
                //
                // The height change IS the motion. The fade only stops the rows
                // being drawn at full strength before there is room for them.
                .transition(.opacity)
            }
        }
    }

    /// How many the list shows once it is open.
    ///
    /// Everything the monitor offers. The cap lives there rather than here, so
    /// there is one answer to "how many are kept" instead of two that can drift.
    private var visibleApps: [AppUsageShare] { monitor.topApps }

    /// The heading, which is also the control.
    ///
    /// A whole row is the target rather than the chevron alone: a 9-point glyph
    /// is a hard thing to hit, and there is nothing else on this row to hit by
    /// mistake.
    ///
    /// Deliberately quieter than the block it belongs to: smaller than the
    /// figure above it, in the label colour, and with no mark of its own. It is
    /// a way into a breakdown of the total, not a reading beside it, and the
    /// commonest way to get a nested list wrong is to draw its heading with the
    /// same weight as the thing it is nested under.
    private var appsHeading: some View {
        Button {
            settings.networkAppsExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("By app")
                    .foregroundStyle(theme.subtitleColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Shut, the heading still answers the question the list exists
                // for. A disclosure that says only "By app" makes somebody open
                // it to find out whether it was worth opening.
                if !settings.networkAppsExpanded, let first = monitor.topApps.first {
                    Text(first.name)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if monitor.topApps.count > 1 {
                        Text("+\(monitor.topApps.count - 1)")
                            .foregroundStyle(theme.subtitleColor)
                            .monospacedDigit()
                    }
                }
                // Said every time, because it is true every time.
                //
                // The total above is built from the kernel's own interface
                // counters, which keep running whether or not this app does —
                // so quitting and reopening loses nothing and the day's figure
                // is the day's figure. These are not. macOS keeps no
                // per-program history at all: the counters live INSIDE each
                // running process and go when it goes, so the only per-program
                // traffic anybody can attribute is traffic that went past while
                // something was watching.
                //
                // That makes this list structurally smaller than the total it
                // sits under, and the difference is a limit to be stated rather
                // than a bug to be fixed. Two words carry it, and the sentence
                // behind them is one hover away.
                if settings.networkAppsExpanded {
                    Text("while running")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.subtitleColor)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.subtitleColor)
                    .rotationEffect(.degrees(settings.networkAppsExpanded ? 0 : -90))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .frame(width: Panel.rowWidth)
            // The whole strip is the button, including the gap in the middle.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.networkAppsExpanded ? Self.whileRunningNote : Self.showNote)
    }

    /// Why this list is smaller than the total above it, put where the
    /// question gets asked — which is while looking at the list.
    private static let whileRunningNote = "Counted only while HashNotch is running. Your Mac keeps no history of which program used what — those counters live inside each running program and go when it does — so traffic that went past while this app was closed is in the total above but cannot be put against any program. The total does not have this limit: it is read from your Mac's own network counters, which keep running whether this app does or not."

    private static let showNote = "Show which programs used the most"


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
