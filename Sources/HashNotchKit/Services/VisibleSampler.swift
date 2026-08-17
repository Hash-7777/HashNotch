import Foundation
import Combine

/// A sampler that runs only while the panel is open.
///
/// A readout that exists solely inside the panel has nothing to say while the
/// panel is shut, so this stops sampling entirely rather than computing values
/// nobody can see. It samples once the instant the panel opens, so the first
/// frame is already current rather than up to one interval stale, and it stops
/// again the moment the panel closes.
///
/// Features that also appear on the strip — media, the timer — need to keep
/// watching whether or not the panel is open, and use `PollingSampler` directly.
@MainActor
public final class VisibleSampler {
    private let interval: TimeInterval
    private let sample: () -> Void
    private let visibility: PanelVisibility
    private var sampler: PollingSampler?
    private var cancellable: AnyCancellable?
    /// A start waiting for the rhythm to come round, held so it can be called
    /// off the moment the panel shuts.
    ///
    /// Without this the delayed start captured its sampler strongly and nothing
    /// could cancel it, so every open scheduled another closure that stayed
    /// alive for up to a whole interval — five minutes, for the token count.
    /// The panel is opened by brushing past the notch, so those stacked up: a
    /// run that opened and closed it eighty times climbed 34 MB doing nothing.
    private var pendingStart: DispatchWorkItem?
    /// When this last read anything, so a reopen does not repeat work that is
    /// still current.
    private var lastSampled = Date.distantPast

    public init(
        interval: TimeInterval,
        visibility: PanelVisibility,
        sample: @escaping () -> Void
    ) {
        self.interval = interval
        self.visibility = visibility
        self.sample = sample
    }

    public func start() {
        cancellable = visibility.$isOpen
            .removeDuplicates()
            .sink { [weak self] open in
                MainActor.assumeIsolated { self?.setRunning(open) }
            }
    }

    public func stop() {
        cancellable = nil
        setRunning(false)
    }

    private func setRunning(_ running: Bool) {
        guard running else {
            pendingStart?.cancel()
            pendingStart = nil
            sampler?.stop()
            sampler = nil
            return
        }
        guard sampler == nil, pendingStart == nil else { return }

        // Sample on open, unless the last one is still fresh.
        //
        // PollingSampler fires once on start, which is what makes the panel
        // open already showing a current value — but the panel is opened by
        // hovering a notch, so it is opened by accident constantly. Without
        // this, brushing past it repeatedly re-ran every reading behind it,
        // and some of those are expensive: the AirPods row spawns a
        // system_profiler, the token row rescans transcripts. A value read two
        // seconds ago is still the value.
        let elapsed = Date().timeIntervalSince(lastSampled)
        guard elapsed < interval else {
            startSampling()
            return
        }

        // Still fresh: show what is already there, and pick the rhythm back up
        // when it would have come round anyway. Nothing is built until then —
        // the work item holds no sampler, and is cancelled if the panel shuts
        // first, so brushing the notch cannot leave anything behind.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStart = nil
            guard self.visibility.isOpen else { return }
            self.startSampling()
        }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (interval - elapsed), execute: work)
    }

    private func startSampling() {
        lastSampled = Date()
        let sampler = PollingSampler(interval: interval) { [weak self] in
            self?.lastSampled = Date()
            self?.sample()
        }
        self.sampler = sampler
        sampler.start()
    }
}
