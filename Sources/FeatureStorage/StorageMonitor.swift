import Foundation
import SwiftUI
import HashNotchKit

/// Publishes how full the startup disk is, while anyone is looking at it.
///
/// A disk does not fill up quickly, and this readout lives only in the panel —
/// so it samples on a `VisibleSampler` and does nothing at all while the panel
/// is shut, which is nearly always.
@MainActor
public final class StorageMonitor: ObservableObject {
    @Published public private(set) var usage: DiskUsage?

    private var sampler: VisibleSampler?

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double) {
        // Half a minute is brisk for something that moves in gigabytes over
        // days; it exists so the number is current when the panel opens rather
        // than to watch the disk change.
        let sampler = VisibleSampler(interval: 30 * scale, visibility: visibility) { [weak self] in
            self?.sample()
        }
        self.sampler = sampler
        sampler.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    private func sample() {
        let fresh = StorageReader.read()
        if fresh != usage { usage = fresh }
    }
}
