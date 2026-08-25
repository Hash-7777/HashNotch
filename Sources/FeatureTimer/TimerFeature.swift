import Foundation
import SwiftUI
import HashNotchKit

/// A countdown timer that lives in the notch: start it from the panel, watch
/// it flank the notch while it runs, and be told when it is up — by the system,
/// on time, whatever this app happens to be doing at that moment.
@MainActor
public final class TimerFeature: NotchFeature {
    public let id = "timer"
    public let title = "Timer"

    private let engine: TimerEngine

    public init(defaults: UserDefaults = .standard) {
        engine = TimerEngine(defaults: defaults)
    }

    /// The countdown itself, so the checks can start one and then do to this
    /// feature what a locked screen does to it. The whole failure this feature
    /// had was in what survives that, and it cannot be measured from outside.
    package var countdown: TimerEngine { engine }

    /// A running countdown is simply still true; a finished one just happened.
    ///
    /// The strip shows one feature at a time, ties going to whichever was
    /// registered first, and media is registered first. At one flat priority
    /// that meant a timer going off while music was playing never reached the
    /// strip at all: the alert sounded and the island went on showing the song,
    /// which is the one moment the island had something more useful to say. The
    /// countdown itself keeps the lower standing — a song you are listening to
    /// beats a number ticking down — and only the finish takes the strip, for
    /// the few seconds it lasts, before handing it back.
    public var livePriority: Int {
        engine.phase == .finished ? LivePriority.announcement : LivePriority.ongoing
    }

    /// Orange, and only while it is going off.
    ///
    /// The same argument the battery makes for its own colours applies: by the
    /// time this is on screen the decision to interrupt has already been taken,
    /// and an announcement arriving with no colour beside ones that have it
    /// reads as the colour having failed. It is also the case the edge exists
    /// for — something worth noticing from across a room without reading a word
    /// of it.
    public var outlineTint: Color? {
        engine.phase == .finished ? .orange : nil
    }

    public func start(context: FeatureContext) { engine.start(presence: context.presence) }

    /// Switched off: the countdown goes, and the alert waiting with the system
    /// goes with it.
    public func stop() { engine.stop() }

    /// The screen went away. The once-a-second wakeup stops; the deadline does
    /// not — see `TimerDeadline` for why a countdown is the one thing here that
    /// survives a lock, and `PowerCoordinator` for why that does not weaken
    /// what the app promises about being locked.
    public func suspend() { engine.suspend() }

    /// The screen is back: work out where the countdown got to, or say it
    /// finished while nobody was looking.
    public func resume(context: FeatureContext) { engine.start(presence: context.presence) }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(TimerIconView(engine: engine, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(TimerTextView(engine: engine, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(TimerDetailView(engine: engine, theme: context.theme))
    }
}
