import SwiftUI
import HashNotchKit

/// How the battery readout is shown.
enum BatteryStyle: String {
    case iconAndPercent
    case percent
    case icon
    case timeRemaining
}

/// Battery level and charging state.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public let title = "Battery"
    public let placement: FeaturePlacement = .trailing
    // Plugged in, unplugged, full, or running out — all of them are moments
    // rather than states, and the low warning is the one message in the app
    // that must not be buried under whatever is playing.
    public let livePriority = LivePriority.announcement

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: BatteryStyle.iconAndPercent.rawValue, title: "Icon and percent"),
        FeatureOption(id: BatteryStyle.percent.rawValue, title: "Percent only"),
        FeatureOption(id: BatteryStyle.icon.rawValue, title: "Icon only"),
        FeatureOption(id: BatteryStyle.timeRemaining.rawValue, title: "Time remaining"),
    ]

    private let monitor = BatteryMonitor()

    public init() {}

    /// Green going on, amber running out — the two the iPhone lights its edge
    /// for, and the two worth seeing without reading anything.
    ///
    /// Deliberately nothing for unplugged or fully charged. Those are also
    /// moments, but neither of them needs acting on, and a colour that appears
    /// for everything stops meaning anything: the low warning has to be the one
    /// that pulls the eye.
    public var outlineTint: Color? { Self.tint(for: monitor.event) }

    /// Pure, and package-visible, because "which moments are worth a colour" is
    /// a decision rather than a detail — and one that is easy to widen by
    /// accident until every event has a colour and none of them mean anything.
    package static func tint(for event: BatteryEvent?) -> Color? {
        switch event {
        case .pluggedIn: return Color(red: 0.30, green: 0.85, blue: 0.39)
        case .lowBattery: return Color(red: 1.0, green: 0.72, blue: 0.20)
        default: return nil
        }
    }

    public func start(context: FeatureContext) { monitor.start(presence: context.presence) }
    public func stop() { monitor.stop() }

    // A Mac with no battery shows nothing at all here rather than a dimmed
    // readout of a battery it does not have. See `BatteryMonitor.isUnavailable`.
    // Answered when the panel is built, which is right for this question: a
    // desktop Mac never grows a battery, and a laptop never loses one.

    public func makeView(context: FeatureContext) -> AnyView {
        guard !monitor.isUnavailable else { return AnyView(EmptyView()) }
        let style = BatteryStyle(rawValue: context.settings.style(for: id)) ?? .iconAndPercent
        return AnyView(BatteryView(monitor: monitor, theme: context.theme, style: style))
    }

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
