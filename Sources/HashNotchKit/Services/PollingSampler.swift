import Foundation

/// A small main-thread timer that calls `tick` on a fixed interval.
///
/// Features use this to sample their data source (network counters, battery,
/// etc.) without each one re-implementing timer plumbing. Fires once
/// immediately on `start()` so the HUD shows a value right away.
@MainActor
public final class PollingSampler {
    private var timer: Timer?
    private let interval: TimeInterval
    private let tick: () -> Void

    public init(interval: TimeInterval, tick: @escaping () -> Void) {
        self.interval = interval
        self.tick = tick
    }

    public func start() {
        stop()
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // A generous tolerance lets macOS coalesce our wakeups with other timers
        // instead of waking the CPU on its own schedule — a large battery win for
        // a background app, at no cost to a once-a-second readout.
        timer.tolerance = interval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
