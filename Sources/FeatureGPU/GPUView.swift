import SwiftUI
import HashNotchKit

/// Expanded detail: graphics load as a number, a graph, or both — laid out
/// exactly like the processor row above it, so the two read as a pair.
struct GPUDetailView: View {
    @ObservedObject var monitor: GPUMonitor
    let theme: Theme
    let style: GPUStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            NotchRow("GPU", icon: .graphics, theme: theme) {
                if style != .graph || !monitor.isAvailable {
                    Text(GPUText.reading(monitor.load, available: monitor.isAvailable))
                        .foregroundStyle(monitor.isAvailable ? tint : theme.subtitleColor)
                        .monospacedDigit()
                        .rollingDigits()
                }
            }
            if style != .number, monitor.isAvailable {
                Sparkline(values: monitor.history, tint: tint, showsScale: true)
                    .frame(width: Panel.rowWidth, height: Panel.graphHeight)
            }
        }
        .figureAnimation(.snappy, value: monitor.load)
    }

    /// The accent until 90% of the graphics processor is in use, then red —
    /// the same rule every full-scale readout follows (`ReadingLevel`).
    private var tint: Color {
        theme.color(for: .of(share: monitor.load ?? 0))
    }
}

/// What the row says. Pure, so the checks can hold it.
package enum GPUText {
    package static func reading(_ load: Double?, available: Bool) -> String {
        guard available else { return "Not reported" }
        guard let load else { return "—" }
        return "\(Int((load * 100).rounded()))%"
    }
}
