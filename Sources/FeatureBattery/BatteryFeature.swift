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
