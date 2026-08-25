import SwiftUI
import HashNotchKit

/// Live activities posted by other apps / scripts / Shortcuts, shown like the
/// iPhone's Live Activities. Reads the local `~/.hashnotch/activities.json` feed.
@MainActor
public final class ActivitiesFeature: NotchFeature {
    public let id = "activities"
    public let title = "Live activities"
    // A posted activity is either something that just finished or something
    // waiting on an answer. Either way it beats a track that will still be
    // playing in ten seconds, and it hands the strip back when it leaves.
    public let livePriority = LivePriority.needsYou

    private let monitor = ActivitiesMonitor()

    public init() {}

    /// The colour worn while something posted is on the strip.
    ///
    /// Taken from the same activity the strip is showing, so the words and the
    /// colour can never describe different things.
    public var outlineTint: Color? { Self.tint(for: monitor.activities.first) }

    /// Green for something that has finished, amber for something waiting on
    /// you, nothing for work still going on.
    ///
    /// The distinction is the one the feed already makes, and it is the
    /// difference between a fact and a request. A notice — anything posted with
    /// a time to dismiss itself after — is a job reporting that it is over: an
    /// AI tool finishing a turn, a build completing. Nothing is being asked of
    /// you and nothing went wrong, so it is green — the same green the battery
    /// wears when it is charging or full, because it is being used to say the
    /// same thing: this is fine, and there is nothing for you to do.
    ///
    /// Something posted with a deadline and no dismissal is waiting for an
    /// answer — the tool that stopped to ask permission, and cannot go on
    /// until somebody replies. That earns amber, because until it is dealt
    /// with, nothing else is happening either.
    ///
    /// Work that is merely in progress gets no colour at all. The strip is
    /// already showing it; lighting the whole island for a download that is
    /// forty percent through would spend the signal on something nobody has to
    /// act on, and a colour that appears for everything announces nothing.
    ///
    /// Deliberately not written in terms of any particular tool. The feed is
    /// open to anything on the Mac that wants to post to it, and the rule is
    /// asked of every poster alike.
    /// The colour for the badge beside the words: the activity's own colour
    /// where it has one, and the app's accent for work that is merely in
    /// progress and lights no edge at all.
    ///
    /// One rule for both the badge and the ring around the notch, because they
    /// are one signal. A green ring with an accent-coloured badge inside it
    /// would read as two things happening at once.
    /// A logo is drawn larger than a symbol, because it is not sitting in one.
    ///
    /// `size` is the room a SYMBOL takes: the glyph plus the tinted disc behind
    /// it. A logo has no disc, so that same room is all artwork, and it can use
    /// more of the strip's height than a badge would.
    ///
    /// It matters more than it sounds. A mark made of fine lines has to survive
    /// being drawn about forty pixels tall — this one's median stroke lands at
    /// three quarters of a pixel at 21 points, which is why it broke up rather
    /// than drew. Every extra point is stroke width it gets back, and rendered
    /// side by side at 21 and 27 the difference is the whole legibility of it.
    ///
    /// Capped well inside the strip's own height so the artwork can never push
    /// the pill taller than the shape it is supposed to sit in.
    package static func logoSide(for size: CGFloat) -> CGFloat {
        min(size * 1.3, size + 8)
    }

    /// How pressing the standing request has become.
    ///
    /// Only a request counts. A notice is already leaving and a job in progress
    /// is not waiting on anybody, so both stay at nothing.
    public var outlineUrgency: Double {
        guard let activity = monitor.activities.first,
              activity.showsCountdown,
              let arrived = monitor.arrived(activity)
        else { return 0 }
        return Self.urgency(waitedSeconds: monitor.now.timeIntervalSince(arrived))
    }

    /// Nothing for the first half minute — long enough to reach for the
    /// keyboard — then rising to full over ten minutes, which is about the
    /// point where a blocked agent has stopped being a pause and started being
    /// a waste of the machine.
    package static func urgency(waitedSeconds: TimeInterval) -> Double {
        let start: TimeInterval = 30
        let full: TimeInterval = 600
        guard waitedSeconds > start else { return 0 }
        return min(1, (waitedSeconds - start) / (full - start))
    }

    package static func markTint(for activity: LiveActivity, accent: Color) -> Color {
        tint(for: activity) ?? accent
    }

    package static func tint(for activity: LiveActivity?) -> Color? {
        guard let activity else { return nil }
        if activity.isNotice { return Color(red: 0.30, green: 0.85, blue: 0.39) }
        if activity.showsCountdown { return Color(red: 1.0, green: 0.72, blue: 0.20) }
        return nil
    }

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence, settings: context.settings)
    }

    public func stop() { monitor.stop() }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesTitleView(monitor: monitor, theme: context.theme))
    }

    /// This feature is the only one that has to be connected to something
    /// outside the app, so it is the only one with a page of its own.
    public func makeSettingsPage(context: FeatureContext) -> FeatureSettingsPage? {
        FeatureSettingsPage(
            title: "Agents",
            symbol: "sparkles",
            view: AnyView(ActivitiesSettingsView(monitor: monitor, theme: context.theme))
        )
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        // The section also appears for the stale-hook notice alone. Without
        // this the one place that could carry the warning is the one place that
        // is hidden whenever there is nothing posted — and a hook too old to
        // post anything is exactly the case it exists for.
        guard !monitor.activities.isEmpty || monitor.hookState.needsAttention else { return nil }
        return AnyView(ActivitiesDetailView(monitor: monitor, theme: context.theme))
    }
}
