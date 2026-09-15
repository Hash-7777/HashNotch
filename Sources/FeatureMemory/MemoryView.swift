import SwiftUI
import HashNotchKit

/// Expanded detail: memory in use as a figure, a graph, or both — laid out
/// exactly like the processor row so the two read as one pair.
struct MemoryDetailView: View {
    @ObservedObject var monitor: MemoryMonitor
    let theme: Theme
    let style: MemoryStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            NotchRow("Memory", icon: .memory, theme: theme) {
                if style != .graph {
                    Text(text)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .rollingDigits()
                }
            }
            if style != .number {
                Sparkline(values: monitor.history, tint: tint, showsScale: true)
                    .frame(width: Panel.rowWidth, height: 26)
            }
        }
        .animation(.snappy, value: monitor.snapshot?.usedBytes)
    }

    /// How much of how much. The total is worth carrying: 12 GB in use means
    /// nothing without knowing whether the machine has 16 or 64.
    private var text: String {
        guard let snapshot = monitor.snapshot else { return "—" }
        switch style {
        case .percent:
            return "\(Int((snapshot.fraction * 100).rounded()))%"
        case .number, .graph, .numberAndGraph:
            return "\(Formatters.bytes(Int64(snapshot.usedBytes))) / \(Formatters.bytes(Int64(snapshot.totalBytes)))"
        }
    }

    /// The accent until 90% of memory is in use, then red — the same rule as
    /// every full-scale readout (`ReadingLevel`).
    private var tint: Color {
        theme.color(for: .of(share: monitor.snapshot?.fraction ?? 0))
    }
}
