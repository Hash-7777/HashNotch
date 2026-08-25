import SwiftUI

/// One selectable way a feature can display itself (e.g. number vs. word vs.
/// symbol). Features declare their options; the settings UI lists them and the
/// feature's view reads the chosen one from `FeatureContext`.
public struct FeatureOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A sideways swipe over the open panel, in the direction the fingers moved.
public enum SwipeDirection: String, Sendable, CaseIterable {
    case left
    case right
}

/// The single contract every feature implements.
///
/// A feature is a self-contained unit: it owns its own data source and its own
/// SwiftUI view. The core never imports a feature and never knows what any
/// feature does — it only sees this protocol. That is what lets features be
/// added or removed without touching core code.
@MainActor
public protocol NotchFeature: AnyObject {
    /// Stable, unique identifier (used for layout identity and settings).
    var id: String { get }

    /// Human-readable name, shown in the expanded panel and settings.
    var title: String { get }

    /// The display styles this feature offers (e.g. number / word / symbol).
    /// The first is the default. Return `[]` for a feature with no choices.
    var displayOptions: [FeatureOption] { get }

    /// Optional richer view shown in the expanded panel when the HUD opens on
    /// hover. Return `nil` (the default) to show nothing extra when expanded.
    func makeExpandedView(context: FeatureContext) -> AnyView?

    /// Optional always-on views shown flanking the notch while something is live
    /// (media playing, an activity running) — like the iPhone's compact Dynamic
    /// Island. Leading sits to the left of the notch, trailing to the right.
    /// Return `nil` (the default) for none.
    ///
    /// Only ONE feature is shown on the strip at a time — see `livePriority`.
    func makeCompactLeadingView(context: FeatureContext) -> AnyView?
    func makeCompactTrailingView(context: FeatureContext) -> AnyView?

    /// Who gets the strip when more than one feature is live at once. Higher
    /// wins; ties go to whichever was registered first.
    ///
    /// The strip is one pill either side of a notch, and its width is fixed by
    /// the hardware, not by how much there is to say. Showing every live
    /// feature at once was never a layout that could work: two features'
    /// content simply overran the budget and spilled across the notch. So the
    /// strip behaves like the thing it imitates — it shows one thing, and the
    /// most urgent thing wins.
    ///
    /// Use `LivePriority` rather than a bare number so the ordering is one
    /// readable list instead of magic constants scattered across modules.
    var livePriority: Int { get }

    /// A colour to trace the island's edge with while this feature holds the
    /// strip, or `nil` (the default) for none.
    ///
    /// The iPhone does this: the edge of the screen glows green while the
    /// charger goes in, red while a call is up. It reads at a glance and from
    /// across a desk, without asking anybody to look at what the words say —
    /// which is the whole appeal of a notch you can see from the corner of your
    /// eye.
    ///
    /// Only the feature that currently owns the strip is asked, so two features
    /// can never argue over the colour: the same rule that decides whose words
    /// are shown decides whose colour is worn. It follows that this is worth
    /// returning only for a state somebody would want to notice ACROSS a room —
    /// a colour that is always on is not a signal, it is decoration, and it
    /// makes the ones that mean something invisible.
    var outlineTint: Color? { get }

    /// How pressing this has become, from 0 to 1.
    ///
    /// The colour says WHAT is happening; this says how long it has been
    /// happening without you. A request that has stood for ten minutes is the
    /// same colour as one that arrived a second ago, and it should not feel the
    /// same — so the line pulses faster and stops dimming as far.
    ///
    /// Nothing else changes: no size, no sound, no second alert. Something you
    /// have not dealt with should press a little harder, not shout, and an
    /// alert that grows is one you end up hiding.
    ///
    /// Zero for everything by default. Only a feature that can be WAITING on
    /// somebody has any business returning more.
    var outlineUrgency: Double { get }

    /// Act on a sideways swipe over the open panel. Return `true` if this
    /// feature took it, `false` (the default) to let another feature try.
    ///
    /// The core does not know what a swipe means any more than it knows what a
    /// feature shows — it only knows the pointer was over the panel and the
    /// fingers went sideways. A feature that has something to do with that says
    /// so by returning true, and the first one to claim it wins, so two
    /// features can never both act on one flick.
    ///
    /// The bar for claiming a swipe is high on purpose: an accidental sideways
    /// nudge while reading the panel must do nothing at all. Claim it only when
    /// there is something obviously in progress that the gesture belongs to.
    func handleSwipe(_ direction: SwipeDirection) -> Bool

    /// Begin sampling / observing. Called when the HUD starts. The context gives
    /// access to shared services (e.g. `presence` for signalling live content).
    func start(context: FeatureContext)

    /// Stop sampling / observing and release resources.
    ///
    /// This is the user having switched the feature OFF, and off means off: no
    /// files opened, no subprocess run, nothing left scheduled anywhere, and
    /// no state kept that would bring any of it back on its own.
    func stop()

    /// The screen has gone away — locked, or asleep — and nobody can see this.
    ///
    /// Stop the work. What separates this from `stop()` is only that the user
    /// has not asked for anything to end: a feature that is holding something
    /// the PERSON created, rather than something it measured, may keep it.
    ///
    /// The default is `stop()`, so a feature that says nothing here behaves
    /// exactly as it did before this existed, and no reading survives a lock by
    /// accident. Only the timer overrides it, and it does so because a
    /// countdown is not a reading — it is a deadline somebody typed in, and
    /// throwing it away when the display sleeps was losing timers.
    func suspend()

    /// The screen is back. Pick up whatever `suspend()` put down.
    ///
    /// The default is `start(context:)`, which is what a feature that keeps
    /// nothing needs.
    func resume(context: FeatureContext)
}

public extension NotchFeature {
    var displayOptions: [FeatureOption] { [] }
    func makeExpandedView(context: FeatureContext) -> AnyView? { nil }
    func makeCompactLeadingView(context: FeatureContext) -> AnyView? { nil }
    func makeCompactTrailingView(context: FeatureContext) -> AnyView? { nil }
    func start(context: FeatureContext) {}
    func stop() {}
    func suspend() { stop() }
    func resume(context: FeatureContext) { start(context: context) }
    var livePriority: Int { LivePriority.ongoing }
    var outlineTint: Color? { nil }
    var outlineUrgency: Double { 0 }
    func handleSwipe(_ direction: SwipeDirection) -> Bool { false }
}

/// The order features take the live strip in, read as one list.
///
/// The rule behind the numbers: something that just HAPPENED beats something
/// that is merely still true. A track plays for an hour and will still be
/// playing in a moment; a job that just finished, a warning about the battery,
/// or a request waiting on an answer each have a few seconds in which they
/// matter, and then never again. Handing those the strip briefly and giving it
/// back is exactly what the iPhone does when a timer goes off over music.
public enum LivePriority {
    /// Something that is simply still true — music, a running timer.
    public static let ongoing = 0
    /// Something that just happened and will leave on its own.
    public static let announcement = 20
    /// Something that has stopped and is waiting on the user.
    public static let needsYou = 40
}
