import SwiftUI
import HashNotchKit

/// Expanded detail: processor load as a number, a graph, or both.
struct CPUDetailView: View {
    @ObservedObject var monitor: CPUMonitor
    let theme: Theme
    let style: CPUStyle

    /// The number keeps its row and the graph goes underneath, at the full width
    /// of the panel — the same arrangement the internet readout uses.
    ///
    /// It used to be a 92-point sparkline squeezed into the row beside the
    /// number, which is too narrow to read a shape in and had nothing to measure
    /// its height against: an idle processor and a busy one drew much the same
    /// squiggle. Full width gives the half-minute room to show, and the floor
    /// and ceiling rules give the height a meaning.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            NotchRow("CPU", icon: .cpu, theme: theme) {
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
        .animation(.snappy, value: monitor.load)
    }

    /// A dash until there are two readings to compare. Better than a confident
    /// 0% for a processor that is plainly doing something.
    private var text: String {
        guard let load = monitor.load else { return "—" }
        return "\(Int((load * 100).rounded()))%"
    }

    /// A processor is worth a glance sooner than a disk is, so these thresholds
    /// are its own. The colours are not: see `ReadingLevel`.
    private var tint: Color {
        theme.color(for: .of(monitor.load ?? 0, caution: 0.6, danger: 0.85))
    }
}
