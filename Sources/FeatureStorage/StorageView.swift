import SwiftUI
import HashNotchKit

/// Expanded detail: how full the disk is, and what the room is going on.
struct StorageDetailView: View {
    @ObservedObject var monitor: StorageMonitor
    let theme: Theme

    var body: some View {
        if let usage = monitor.usage {
            VStack(alignment: .leading, spacing: 7) {
                // "STORAGE", not the volume's name. Almost every Mac's startup
                // disk is still called Macintosh HD, which names the hardware
                // rather than the thing being reported and reads as a label
                // nobody got round to changing.
                NotchSectionHeader("STORAGE", icon: .storage, theme: theme)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(usage.percentUsed)%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                        .rollingDigits()
                    Text("full")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                    Spacer(minLength: 8)
                    Text("\(Formatters.bytes(usage.freeBytes)) free")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                        .monospacedDigit()
                }

                bar(usage)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
            .animation(.snappy, value: usage.percentUsed)
        }
    }

    /// One bar in two parts: what is in use, and what is free.
    ///
    /// It used to have a third, middle band for space macOS said it would hand
    /// back. That band was removed with the figure behind it — see
    /// `StorageReader` — because it was reporting two thirds of this disk as
    /// about to return, and nothing else on the Mac agreed.
    ///
    /// The parts are not labelled underneath. This is a glanceable panel with
    /// eleven other indicators in it, and a row of legend costs more height than
    /// the words are worth: the percentage above already says how full, and the
    /// figure beside it already says how much is left.
    private func bar(_ usage: DiskUsage) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(usage.segments, id: \.kind) { segment in
                    Rectangle()
                        .fill(color(for: segment.kind))
                        .frame(width: max(0, geo.size.width * CGFloat(segment.fraction)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
        .help(tooltip(usage))
    }

    private func tooltip(_ usage: DiskUsage) -> String {
        usage.segments
            .filter { $0.fraction > 0.001 }
            .map { "\($0.kind.label): \(Formatters.bytes(Int64(Double(usage.totalBytes) * $0.fraction)))" }
            .joined(separator: " · ")
    }

    private func color(for kind: DiskUsage.Segment) -> Color {
        switch kind {
        case .taken: return fill
        case .free: return Color.white.opacity(0.12)
        }
    }

    /// Quiet until it matters. A disk at 70% is simply a disk; one with almost
    /// nothing left is the reason you opened the panel. In percent, which is
    /// what this readout measures in.
    private var fill: Color {
        theme.color(for: .of(Double(monitor.usage?.percentUsed ?? 0), caution: 75, danger: 90))
    }
}
