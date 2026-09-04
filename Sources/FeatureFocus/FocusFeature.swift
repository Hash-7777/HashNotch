import SwiftUI
import HashNotchKit

/// A focus cycle, and an honest account of the day it added up to.
///
/// The cycle itself is the ordinary one: a stretch of work, a short rest, and a
/// longer rest every fourth time. What is not ordinary is what it will not do.
/// Every tracker of this kind is self-reported — you start it, you forget to
/// stop it, and the number at the end of the week is a guess wearing a decimal
/// point. This one already knows when the screen went away, because the app was
/// watching for other reasons entirely, so a piece of work you walked out of
/// ends when you left, counts only what it served, and is recorded as not
/// finished. A tally that counted a locked Mac as focus would be a wish with a
/// number beside it.
///
/// Nothing about the day leaves the Mac, which is the whole reason a thing like
/// this belongs in an app like this one rather than in a corporate tracker.
@MainActor
public final class FocusFeature: NotchFeature {
    public let id = "focus"
    public let title = "Focus"

    /// It holds the strip for as long as a block runs, which is the ordinary
    /// case for something in progress rather than something announcing itself.
    public let livePriority = LivePriority.ongoing

    private let engine = FocusEngine()
    private var context: FeatureContext?

    public init() {}

    /// The accent while work is running, and nothing at all during a rest.
    ///
    /// A colour that is always on is decoration; the point of the edge is that
    /// it means something across a room, and what it means here is "you are
    /// meant to be working".
    public var outlineTint: Color? {
        guard let session = engine.session, session.block.isWork else { return nil }
        return context?.theme.accent
    }

    public func start(context: FeatureContext) {
        self.context = context
        engine.start(presence: context.presence, away: context.away, defaults: .standard)
    }

    public func stop() { engine.stop() }

    /// A block is a deadline somebody set for themselves, not a reading, so it
    /// is kept across a lock exactly as the countdown is. The clock stops
    /// because nothing is on screen to run it.
    public func suspend() { engine.suspend() }

    public func resume(context: FeatureContext) { start(context: context) }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(FocusIconView(engine: engine, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(FocusTitleView(engine: engine, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(FocusDetailView(engine: engine, theme: context.theme))
    }

    public func makeSettingsPage(context: FeatureContext) -> FeatureSettingsPage? {
        FeatureSettingsPage(
            title: "Focus",
            symbol: "target",
            view: AnyView(FocusSettingsView(engine: engine, theme: context.theme))
        )
    }
}
