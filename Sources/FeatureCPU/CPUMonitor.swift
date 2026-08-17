import Foundation
import SwiftUI
import HashNotchKit

/// Publishes processor load, and the shape of the last little while.
///
/// Load is a difference between two tick readings, so the first sample after
/// opening the panel produces no number — there is nothing yet to compare it
/// with. The reading after it, a second later, is the first real one.
@MainActor
public final class CPUMonitor: ObservableObject {
    /// 0...1, or nil until two readings exist.
    @Published public private(set) var load: Double?
    /// Recent loads, oldest first, for the graph.
    @Published public private(set) var history: [Double] = []

    /// Half a minute at a sample a second. Long enough to show a spike that has
    /// already passed, short enough to still be about now.
    private static let historyLength = 30

    private var sampler: VisibleSampler?
    private var previous: CPUTicks?

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double) {
        // A second is the natural grain: the counters are ticks, and a shorter
        // window divides two small numbers and reports noise as load.
        let sampler = VisibleSampler(interval: 1.0 * scale, visibility: visibility) { [weak self] in
            self?.sample()
        }
        self.sampler = sampler
        sampler.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        // Drop the baseline as well as the samples. Comparing against a reading
        // from before the panel was last shut would report the average across
        // the gap — which could be hours — as though it were the load now.
        previous = nil
        load = nil
        history = []
    }

    private func sample() {
        guard let now = CPUReader.ticks() else { return }
        defer { previous = now }
        guard let previous, let value = previous.load(to: now) else { return }

        load = value
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }
}
