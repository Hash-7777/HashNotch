import SwiftUI
import HashNotchKit

/// How the processor readout is shown.
package enum CPUStyle: String {
    case numberAndGraph
    case number
    case graph
}

/// How busy the processor is. Panel only: it is a number you look up, not one
/// worth a permanent place beside the notch.
@MainActor
public final class CPUFeature: NotchFeature {
    public let id = "cpu"
    public let title = "CPU"

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: CPUStyle.numberAndGraph.rawValue, title: "Number and graph"),
        FeatureOption(id: CPUStyle.number.rawValue, title: "Number only"),
        FeatureOption(id: CPUStyle.graph.rawValue, title: "Graph only"),
    ]

    private let monitor = CPUMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(visibility: context.visibility, scale: context.settings.samplingScale)
    }

    public func stop() { monitor.stop() }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(CPUDetailView(
            monitor: monitor,
            theme: context.theme,
            style: CPUStyle(rawValue: context.settings.style(for: id)) ?? .numberAndGraph
        ))
    }
}
