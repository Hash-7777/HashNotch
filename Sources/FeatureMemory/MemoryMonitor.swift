import Foundation
import SwiftUI
import HashNotchKit

/// Publishes how much memory is in use, and the shape of the last little while.
///
/// Unlike the processor, a single reading is already an answer — memory in use
/// is a level, not a rate — so the first sample after the panel opens is a real
/// number rather than a dash.
@MainActor
public final class MemoryMonitor: ObservableObject {
    @Published public private(set) var snapshot: MemorySnapshot?
    /// Recent readings, oldest first, for the graph.
    @Published public private(set) var history: [Double] = []

    /// Half a minute at a sample a second, matching the processor graph so the
    /// two can be read against each other.
    private static let historyLength = 30

    private var sampler: VisibleSampler?

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double) {
        let sampler = VisibleSampler(interval: 1.0 * scale, visibility: visibility) { [weak self] in
            self?.sample()
        }
        self.sampler = sampler
        sampler.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        // Drop the shape as well as the reading. A graph resuming with samples
        // from before the panel was last shut would draw a jump that never
        // happened across a gap that could be hours.
        snapshot = nil
        history = []
    }

    private func sample() {
        guard let fresh = MemoryReader.read() else { return }
        if fresh != snapshot { snapshot = fresh }
        history.append(fresh.fraction)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }
}
