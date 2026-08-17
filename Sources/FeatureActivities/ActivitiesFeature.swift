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
