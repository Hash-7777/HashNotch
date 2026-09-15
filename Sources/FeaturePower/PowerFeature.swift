import SwiftUI
import HashNotchKit

/// How much power the Mac is using right now. Panel only, and only on a Mac
/// that answers — see `PowerReader` for where the figure comes from.
@MainActor
public final class PowerFeature: NotchFeature {
    public let id = "power"
    public let title = "Power consumption"
    public let displayOptions: [FeatureOption] = []

    private let monitor = PowerMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(visibility: context.visibility, scale: context.settings.samplingScale)
    }

    public func stop() { monitor.stop() }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard monitor.isAvailable else { return nil }
        return AnyView(PowerDetailView(monitor: monitor, theme: context.theme))
    }
}
