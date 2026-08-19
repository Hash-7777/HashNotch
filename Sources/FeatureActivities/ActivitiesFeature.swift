import SwiftUI
import HashNotchKit

/// Live activities posted by other apps / scripts / Shortcuts, shown like the
/// iPhone's Live Activities. Reads the local `~/.hashnotch/activities.json` feed.
@MainActor
public final class ActivitiesFeature: NotchFeature {
    public let id = "activities"
    public let title = "Live activities"
    public let placement: FeaturePlacement = .leading
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

    /// Blue for something that has finished, amber for something waiting on
    /// you, nothing for work still going on.
    ///
    /// The distinction is the one the feed already makes, and it is the
    /// difference between a fact and a request. A notice — anything posted with
    /// a time to dismiss itself after — is a job reporting that it is over: an
    /// AI tool finishing a turn, a build completing. Nothing is being asked of
    /// you, so it is blue, the app's own colour, which says "read me" without
    /// saying "now".
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
    package static func tint(for activity: LiveActivity?) -> Color? {
        guard let activity else { return nil }
        if activity.isNotice { return Color(red: 0.25, green: 0.55, blue: 1.0) }
        if activity.showsCountdown { return Color(red: 1.0, green: 0.72, blue: 0.20) }
        return nil
    }

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence, settings: context.settings)
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        // Nothing in the hover row; activities live in the compact strip + detail.
        AnyView(EmptyView())
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesTitleView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard !monitor.activities.isEmpty else { return nil }
        return AnyView(ActivitiesDetailView(monitor: monitor, theme: context.theme))
    }
}
