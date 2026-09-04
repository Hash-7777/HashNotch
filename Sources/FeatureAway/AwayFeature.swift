import SwiftUI
import HashNotchKit

/// Compact-live: a small mark left of the notch while the digest is up.
struct AwayIconView: View {
    @ObservedObject var report: AwayReport
    let theme: Theme

    var body: some View {
        if report.line != nil {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Compact-live: the line itself, right of the notch.
struct AwayTextView: View {
    @ObservedObject var report: AwayReport
    let theme: Theme

    var body: some View {
        if let line = report.line {
            MarqueeText(line)
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: 140, alignment: .leading)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Expanded: the same digest with room to breathe, one change per line.
struct AwayDetailView: View {
    @ObservedObject var report: AwayReport
    let theme: Theme

    var body: some View {
        if report.line != nil {
            VStack(alignment: .leading, spacing: 7) {
                NotchSectionHeader("WHILE YOU WERE AWAY", icon: .away, theme: theme)

                Text(AwayDigest.awayText(report.awayFor))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textColor)

                ForEach(Array(report.changes.enumerated()), id: \.offset) { _, change in
                    Text(AwayDigest.text(for: change))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.subtitleColor)
                }

                // Said plainly, because a readout about the past invites exactly
                // one question and it should not have to be asked.
                Text("Counted from what the indicators were already keeping. Nothing new is read to say this.")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
    }
}

/// What happened while nobody was looking.
///
/// The only readout in this app about the PAST. Everything else answers what is
/// true now; this answers what was missed, which macOS answers nowhere — you
/// shut the lid, come back two hours later, and nothing tells you a download
/// finished or that the battery fell eighteen points in a bag.
///
/// It reads nothing of its own. Every number in the line was already being kept
/// and already being shown by another indicator; the core subtracts two moments
/// of them and hands the result here. See `AwayDigest`.
@MainActor
public final class AwayFeature: NotchFeature {
    public let id = "away"
    public let title = "While you were away"

    /// An announcement, like a finished download: it matters for a few seconds
    /// and then never again. It must never sit on top of music for an hour.
    public let livePriority = LivePriority.announcement

    private var report: AwayReport?
    private var clearWork: DispatchWorkItem?
    private weak var presence: LivePresence?

    public init() {}

    /// How long the line stays up. Long enough to read twice, short enough that
    /// it is gone before it becomes part of the furniture.
    private static let showFor: TimeInterval = 12

    public func start(context: FeatureContext) {
        let report = context.away
        self.report = report
        self.presence = context.presence
        // The core posts a digest at most once per absence, so this watches
        // rather than samples: there is nothing to poll.
        observe(report)
    }

    public func stop() {
        clearWork?.cancel()
        clearWork = nil
        report?.clear()
        presence?.setActive(id, false)
        cancellable = nil
        report = nil
    }

    private var cancellable: Any?

    private func observe(_ report: AwayReport) {
        cancellable = report.objectWillChange.sink { [weak self, weak report] _ in
            MainActor.assumeIsolated {
                guard let self, let report else { return }
                // objectWillChange fires BEFORE the value lands, so the decision
                // is deferred by one turn of the loop rather than read early.
                DispatchQueue.main.async { self.digestChanged(report) }
            }
        }
    }

    private func digestChanged(_ report: AwayReport) {
        guard report.line != nil else {
            presence?.setActive(id, false)
            return
        }
        presence?.setActive(id, true)
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.report?.clear()
                self.presence?.setActive(self.id, false)
            }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showFor, execute: work)
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(AwayIconView(report: context.away, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(AwayTextView(report: context.away, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard context.away.line != nil else { return nil }
        return AnyView(AwayDetailView(report: context.away, theme: context.theme))
    }
}
