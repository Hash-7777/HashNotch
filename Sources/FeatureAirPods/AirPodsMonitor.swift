import Foundation
import HashNotchKit

/// Publishes AirPods battery, and nothing while no pair is connected. Polls at a
/// low frequency off the main thread — battery moves slowly and each read spawns
/// a short `system_profiler`. Sampling stops with the app / on screen sleep via
/// the usual feature lifecycle, so it is idle when it should be.
@MainActor
public final class AirPodsMonitor: ObservableObject {
    @Published public private(set) var battery: AirPodsBattery?

    private var sampler: VisibleSampler?
    private let queue = DispatchQueue(label: "com.hashnotch.airpods", qos: .utility)
    private var inFlight = false

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double = 1) {
        sample()
        // Each sample runs system_profiler, a whole subprocess. Doing that
        // every twenty seconds for a readout nobody can see was the single most
        // expensive idle habit the app had.
        sampler = VisibleSampler(interval: 60.0 * scale, visibility: visibility) { [weak self] in
            self?.sample()
        }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if battery != nil { battery = nil }
    }

    /// Read off-main (it's a subprocess), publish on main. Skips if a previous
    /// read is still running so slow reads never stack up.
    private func sample() {
        guard !inFlight else { return }
        inFlight = true
        queue.async { [weak self] in
            let result = AirPodsReader.read()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                if self.battery != result { self.battery = result }
            }
        }
    }
}
