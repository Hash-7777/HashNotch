import SwiftUI

/// Where a feature is placed in the notch HUD.
public enum FeaturePlacement: String, Sendable, CaseIterable, Codable {
    /// Compact readout to the left of the physical notch.
    case leading
    /// Compact readout to the right of the physical notch.
    case trailing
    /// Shown only in the expanded panel below the notch.
    case expanded

    /// Friendly label for the settings UI.
    public var label: String {
        switch self {
        case .leading: return "Left of notch"
        case .trailing: return "Right of notch"
        case .expanded: return "Expanded only"
        }
    }
}

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

    /// Default placement when the user has not chosen one. The live placement
    /// comes from settings, so the user can move features left or right.
    var placement: FeaturePlacement { get }

    /// The display styles this feature offers (e.g. number / word / symbol).
    /// The first is the default. Return `[]` for a feature with no choices.
    var displayOptions: [FeatureOption] { get }

    /// Build the compact SwiftUI view shown around the notch. Main actor.
    /// Read the chosen style from `context.settings.style(for: id)`.
    func makeView(context: FeatureContext) -> AnyView

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
    func stop()
}

public extension NotchFeature {
    var displayOptions: [FeatureOption] { [] }
    func makeExpandedView(context: FeatureContext) -> AnyView? { nil }
    func makeCompactLeadingView(context: FeatureContext) -> AnyView? { nil }
    func makeCompactTrailingView(context: FeatureContext) -> AnyView? { nil }
    func start(context: FeatureContext) {}
    func stop() {}
    var livePriority: Int { LivePriority.ongoing }
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
