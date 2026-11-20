import Foundation
import SwiftUI
import HashNotchKit

/// Publishes how busy the graphics processor is, and the shape of the last
/// little while.
@MainActor
public final class GPUMonitor: ObservableObject {
    /// 0...1, or nil until the first reading.
    @Published public private(set) var load: Double?
    /// Recent loads, oldest first, for the graph.
    @Published public private(set) var history: [Double] = []
    /// False once a reading has been asked for and this Mac gave none, so the
    /// row can say so instead of holding a dash forever.
    @Published public private(set) var isAvailable = true

    /// Half a minute at a sample a second, matching the processor graph so the
    /// two can be read against each other.
    private static let historyLength = 30

    private var sampler: VisibleSampler?
    private let read: () -> Double?

    /// `read` is a parameter so the checks can drive the monitor without a
    /// graphics processor; the app always uses the registry.
    public convenience init() { self.init(read: GPUReader.read) }

    package init(read: @escaping () -> Double?) {
        self.read = read
    }

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
        // Drop the shape as well as the reading, for the same reason the
        // processor does: a graph that resumed with samples from before the
        // panel was last shut would draw a line across a gap it never measured.
        load = nil
        history = []
        isAvailable = true
    }

    package func sample() {
        guard let value = read() else {
            if isAvailable { isAvailable = false }
            return
        }
        if !isAvailable { isAvailable = true }
        load = value
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }
}
