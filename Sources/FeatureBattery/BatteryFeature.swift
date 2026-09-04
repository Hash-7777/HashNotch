import SwiftUI
import HashNotchKit

/// How the battery readout is shown.
/// How the battery row reads.
///
/// There used to be a fourth, "Icon only", and it went when the compact pills
/// did. It meant something on a pill beside the notch — a battery drawn with no
/// figure — and nothing in the panel, where a row labelled Battery with no
/// reading after it is not a readout, so the panel showed the percentage
/// anyway. With the pill gone it was the same row as "Icon and percent" under a
/// different name, which is a worse thing to offer than one option fewer.
package enum BatteryStyle: String {
    case iconAndPercent
    case percent
    case timeRemaining
}

/// Battery level and charging state.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public let title = "Battery"
    // Plugged in, unplugged, full, or running out — all of them are moments
    // rather than states, and the low warning is the one message in the app
    // that must not be buried under whatever is playing.
    public let livePriority = LivePriority.announcement

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: BatteryStyle.iconAndPercent.rawValue, title: "Icon and percent"),
        FeatureOption(id: BatteryStyle.percent.rawValue, title: "Percent only"),
        FeatureOption(id: BatteryStyle.timeRemaining.rawValue, title: "Time remaining"),
    ]

    private let monitor = BatteryMonitor()

    public init() {}

    public var outlineTint: Color? { Self.tint(for: monitor.event) }

    /// Every battery moment gets its own colour, and they are different from
    /// each other on purpose.
    ///
    /// This started out lighting only the charger going in and the battery
    /// running out, on the argument that a colour appearing for everything
    /// stops meaning anything. That argument was wrong here, and the reason is
    /// worth keeping: these four are not "everything". The strip already only
    /// appears for a moment worth announcing, so by the time one of them is on
    /// screen the decision to interrupt has been taken — and an announcement
    /// that arrives with no colour beside three that do reads as the colour
    /// having failed, not as restraint.
    ///
    /// Pure and package-visible, because which colour goes with which moment is
    /// a decision rather than a detail.
    package static func tint(for event: BatteryEvent?) -> Color? {
        switch event {
        // Going on, and the charge being done: both good news, both green, the
        // colour the phone uses for exactly this.
        case .pluggedIn, .fullyCharged:
            return Color(red: 0.30, green: 0.85, blue: 0.39)
        // Running out. The one that needs doing something about, so it takes
        // the colour the eye is quickest to.
        case .lowBattery:
            return Color(red: 1.0, green: 0.55, blue: 0.10)
        // Off the charger and running on its own. White, because this is the
        // one of the four that reports rather than warns — it is the absence of
        // a state, not an event to act on — and white is the only colour that
        // says "no colour" while still being visible on black.
        case .unplugged:
            return Color(white: 0.96)
        case .none:
            return nil
        }
    }

    /// The level, not a total — so this is the one figure that can move both
    /// ways, and the one whose sign carries the meaning. A battery that fell
    /// fourteen points in a bag is the whole reason somebody reads this line.
    public var awayFigure: AwayFigure? {
        AwayFigure(
            id: "battery.percent",
            noun: "battery",
            value: Double(monitor.percentage),
            unit: .percent
        )
    }

    public func start(context: FeatureContext) { monitor.start(presence: context.presence) }
    public func stop() { monitor.stop() }

    // A Mac with no battery shows nothing at all here rather than a dimmed
    // readout of a battery it does not have. See `BatteryMonitor.isUnavailable`.
    // Answered when the panel is built, which is right for this question: a
    // desktop Mac never grows a battery, and a laptop never loses one.

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        guard !monitor.isUnavailable else { return nil }
        return AnyView(BatteryEventIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        guard !monitor.isUnavailable else { return nil }
        return AnyView(BatteryEventTextView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard !monitor.isUnavailable else { return nil }
        return AnyView(BatteryDetailView(
            monitor: monitor,
            settings: context.settings,
            theme: context.theme,
            style: BatteryStyle(rawValue: context.settings.style(for: id)) ?? .iconAndPercent
        ))
    }
}
