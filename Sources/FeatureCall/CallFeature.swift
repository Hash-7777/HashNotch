import SwiftUI
import HashNotchKit

/// Shows when an app has your microphone open — a call, a meeting, a recording
/// — with that app's own icon, a live dot, and how long it has been going.
///
/// Deliberately not called "Calls". It does not know what a call is: it knows
/// an application opened an input stream. That happens to cover FaceTime, Zoom,
/// Teams, Meet in a browser, a voice note and a game with push-to-talk, all
/// without any of them being named anywhere — and it means the readout can
/// never claim to know more than it does.
@MainActor
public final class CallFeature: NotchFeature {
    public let id = "call"
    public let title = "Microphone"
    public let placement: FeaturePlacement = .leading

    /// Above music, below anything asking for an answer. Somebody's microphone
    /// being live outranks what is playing — it is the thing they would want to
    /// know first if they had forgotten it.
    public let livePriority = LivePriority.announcement

    private let monitor = CallMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence)
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(CallIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(CallTitleView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard monitor.use != nil else { return nil }
        return AnyView(CallDetailView(monitor: monitor, theme: context.theme))
    }
}
