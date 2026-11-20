import SwiftUI
import HashNotchKit

/// How the memory readout is shown.
package enum MemoryStyle: String {
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

    /// The share in use, on the menu bar's clock, while it is in the menu bar.
    public var menuBarMeter: MenuBarMeter? {
        MenuBarMeter(
            id: id,
            title: title,
            summary: "How much of the memory is in use.",
            label: "MEM",
            glyph: .memory,
            widestText: "100%"
        ) {
            { MemoryReader.read().map { MenuBarReading.share($0.fraction, title: "Memory") } }
        }
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(MemoryDetailView(
            monitor: monitor,
            theme: context.theme,
            style: MemoryStyle(rawValue: context.settings.style(for: id)) ?? .numberAndGraph
        ))
    }
}
