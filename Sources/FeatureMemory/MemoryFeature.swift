import SwiftUI
import HashNotchKit

/// How the memory readout is shown.
enum MemoryStyle: String {
    case numberAndGraph
    case number
    case graph
    case percent
}

/// How much of the Mac's memory is in use.
///
/// On Apple Silicon the processor and the graphics share one pool, so this is
/// the whole machine's memory rather than a figure for either on its own.
///
/// Panel only, like the processor: it is a number you look up when something
/// feels slow, not one worth a permanent place beside the notch.
@MainActor
public final class MemoryFeature: NotchFeature {
    public let id = "memory"
    public let title = "Memory"
    public let placement: FeaturePlacement = .expanded

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: MemoryStyle.numberAndGraph.rawValue, title: "Amount and graph"),
        FeatureOption(id: MemoryStyle.number.rawValue, title: "Amount only"),
        FeatureOption(id: MemoryStyle.percent.rawValue, title: "Percentage"),
        FeatureOption(id: MemoryStyle.graph.rawValue, title: "Graph only"),
    ]

    private let monitor = MemoryMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(visibility: context.visibility, scale: context.settings.samplingScale)
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(MemoryDetailView(
            monitor: monitor,
            theme: context.theme,
            style: MemoryStyle(rawValue: context.settings.style(for: id)) ?? .numberAndGraph
        ))
    }
}
