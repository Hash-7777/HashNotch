import Foundation
import IOKit
import HashNotchKit

/// Publishes the Mac's power draw, and the shape of the last minute of it.
///
/// Panel only. The draw is a number you look up, and nothing is added up over
/// time, so there is no reason to read it while nobody is looking.
@MainActor
public final class PowerMonitor: ObservableObject {
    /// Watts, or nil until the first reading.
    @Published public private(set) var watts: Double?
    /// The charger's rating while one is connected, for the red point and the
    /// graph's limit line.
    @Published public private(set) var chargerWatts: Double?
    /// Recent draws in watts, oldest first.
    @Published public private(set) var history: [Double] = []

    /// Whether this Mac answers at all. Decided once at start, by asking: a Mac
    /// that gives no figure then will not give one later, and the row should
    /// not appear rather than sit there saying nothing.
    public private(set) var isAvailable = false

    /// Half a minute at a reading a second, like the processor's graph.
    private static let historyLength = 30

    private var sampler: VisibleSampler?
    private var smc: SMCConnection?
    private var service: io_service_t = 0

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double) {
        smc = SMCConnection()
        service = PowerReader.batteryService()
        isAvailable = PowerReader.read(smc: smc, battery: service) != nil
        guard isAvailable else { release(); return }
        // A second: the SMC's system total refreshes once a second, so a
        // faster read would redraw the same figure and a slower one would
        // miss the spikes the graph is for.
        let sampler = VisibleSampler(interval: 1.0 * scale, visibility: visibility) { [weak self] in
            self?.sample()
        }
        self.sampler = sampler
        sampler.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        release()
        // The graph is about the last minute. Kept across a stop it would join
        // a line from before the panel was shut to one from after, and draw a
        // gap of any length as a single step.
        watts = nil
        chargerWatts = nil
        history = []
    }

    private func release() {
        smc = nil
        if service != 0 { IOObjectRelease(service) }
        service = 0
    }

    private func sample() {
        guard let reading = PowerReader.read(smc: smc, battery: service) else { return }
        watts = reading
        let charger = PowerReader.chargerWatts()
        if chargerWatts != charger { chargerWatts = charger }
        history.append(reading)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }
}
