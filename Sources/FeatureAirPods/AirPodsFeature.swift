import SwiftUI
import HashNotchKit

/// AirPods battery — Left, Right, and Case — shown in the expanded panel while a
/// pair is connected, and nothing when it isn't. A self-contained feature: it
/// owns its reader, its monitor, and its view, and depends only on the core.
@MainActor
public final class AirPodsFeature: NotchFeature {
    public let id = "airpods"
    public let title = "AirPods"
    public let placement: FeaturePlacement = .expanded

    private let monitor = AirPodsMonitor()

    public init() {}

    public func start(context: FeatureContext) { monitor.start(visibility: context.visibility, scale: context.settings.samplingScale) }
    public func stop() { monitor.stop() }

    // Required by the protocol; the island renders the compact strip and the
    // expanded panel separately, and AirPods is panel-only — so the compact
    // view is intentionally empty and everything lives in the expanded view.

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard monitor.battery != nil else { return nil }
        return AnyView(AirPodsDetailView(monitor: monitor, theme: context.theme))
    }
}
