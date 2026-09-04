import SwiftUI
import HashNotchKit

/// Shows when an app has your microphone or a camera open — a call, a meeting, a
/// recording — with that app's own icon, a live dot, and how long it has been
/// going.
///
/// Deliberately not called "Calls". It does not know what a call is: it knows an
/// application opened an input stream, and that a camera is running. That
/// happens to cover FaceTime, Zoom, Teams, Meet in a browser, a voice note and a
/// game with push-to-talk, all without any of them being named anywhere — and it
/// means the readout can never claim to know more than it does.
///
/// One indicator for both, not two. Something using both is one thing happening,
/// and the pair is worth more than either half: it is what tells you at a glance
/// that you are heard but not seen, or seen but not heard, which is the thing
/// people get wrong in a meeting. Two indicators could not say that — they would
/// be two rows, and only one of them can hold the strip at a time.
@MainActor
public final class CallFeature: NotchFeature {
    public let id = "call"
    public let title = "Microphone and camera"

    /// Above music, below anything asking for an answer. Somebody's microphone
    /// being live outranks what is playing — it is the thing they would want to
    /// know first if they had forgotten it.
    public let livePriority = LivePriority.announcement

    private let monitor = CallMonitor()

    public init() {}

    /// Red while a microphone or a camera is open, which is the one state on this
    /// machine that somebody would want to see from the other side of the room —
    /// the same red every camera and recorder has used for a century, and the
    /// same signal macOS puts in the menu bar, said where the eye already is.
    public var outlineTint: Color? {
        monitor.use == nil ? nil : Color(red: 1.0, green: 0.27, blue: 0.27)
    }

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence)
    }

    public func stop() { monitor.stop() }

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
