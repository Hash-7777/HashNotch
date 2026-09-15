import Foundation
import IOKit
import HashNotchKit

/// Publishes the Mac's power draw.
///
/// Panel only. The draw is a number you look up, and nothing is added up over
/// time, so there is no reason to read it while nobody is looking.
@MainActor
public final class PowerMonitor: ObservableObject {
    /// Watts, or nil until the first reading.
    @Published public private(set) var watts: Double?
    /// The charger's rating while one is connected, for the red point.
    @Published public private(set) var chargerWatts: Double?

    /// Whether this Mac answers at all. Decided once at start, by asking: a Mac
    /// that gives no figure then will not give one later, and the row should
    /// not appear rather than sit there saying nothing.
    public private(set) var isAvailable = false

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
        // show a number that is no longer "right now".
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
        // A figure from before the panel was shut is not "right now" when it
        // opens again, so it goes rather than being shown until the next read.
        watts = nil
        chargerWatts = nil
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
    }
}
