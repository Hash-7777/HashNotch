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

    /// Load, on the menu bar's clock, while it is in the menu bar. The reader
    /// takes its first counter reading as it is built, so its first tick has
    /// something to measure the load over.
    public var menuBarMeter: MenuBarMeter? {
        MenuBarMeter(
            id: id,
            title: title,
            summary: "How busy the processor is.",
            label: "CPU",
            glyph: .cpu,
            widestText: "100%"
        ) {
            let tracker = CPULoadTracker()
            _ = tracker.next()
            return { tracker.next().map { MenuBarReading.share($0, title: "CPU") } }
        }
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(CPUDetailView(
            monitor: monitor,
            theme: context.theme,
            style: CPUStyle(rawValue: context.settings.style(for: id)) ?? .numberAndGraph
        ))
    }
}
