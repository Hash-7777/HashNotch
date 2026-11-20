import SwiftUI
import HashNotchKit

/// How the graphics readout is shown. The same three choices the processor
/// offers, because the two rows sit together and are read against each other.
package enum GPUStyle: String {
    case numberAndGraph
    case number
    case graph
}

/// How busy the graphics processor is. Panel only, like the processor.
@MainActor
public final class GPUFeature: NotchFeature {
    public let id = "gpu"
    public let title = "GPU"

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: GPUStyle.numberAndGraph.rawValue, title: "Number and graph"),
        FeatureOption(id: GPUStyle.number.rawValue, title: "Number only"),
        FeatureOption(id: GPUStyle.graph.rawValue, title: "Graph only"),
    ]

    private let monitor = GPUMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(visibility: context.visibility, scale: context.settings.samplingScale)
    }

    public func stop() { monitor.stop() }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(GPUDetailView(
            monitor: monitor,
            theme: context.theme,
            style: GPUStyle(rawValue: context.settings.style(for: id)) ?? .numberAndGraph
        ))
    }
}
