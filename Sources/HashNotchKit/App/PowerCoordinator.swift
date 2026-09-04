import AppKit

/// Stops the island when nobody can see it, and hides it outright when nobody
/// should.
///
/// Two different states, and they are not the same thing:
///
/// **Screen asleep.** Sampling nothing when nobody is looking is the single
/// biggest battery win: no timers fire, no work happens, until the display
/// comes back. Combined with the tolerant, coalesced timers in
/// `PollingSampler`, the app's idle cost is effectively nil.
///
/// **Screen locked.** The display is ON and somebody is standing in front of
/// it — just not necessarily you. A notch that carries what you are listening
/// to, which app has your microphone, how much you have spent on AI today and
/// what your machine is doing is a summary of your afternoon, and a locked Mac
/// is precisely the moment none of that should be readable. macOS puts the
/// login window above ordinary windows, so in practice the island is already
/// covered — but "in practice" and "covered" are not the same as "not there",
/// and this is the one claim where that difference matters. The overlay is
/// taken off screen and every feature is put down, so there is nothing to be
/// covered and nothing being read while the Mac is locked.
///
/// **Put down, not switched off.** The two are not the same and the difference
/// costs a timer. Everything a feature MEASURES stops either way — that is what
/// the claim above is about, and `suspend()` falls back to `stop()` so a
/// feature that says nothing on the subject cannot leak a reading through this
/// door. What may survive is something the PERSON created rather than something
/// the app read: a countdown they set themselves. Before this, locking the Mac
/// or letting the display sleep silently threw a running timer away — no alert,
/// no countdown, and nothing anywhere saying one had been set. A display that
/// sleeps after ten minutes is not an unusual thing to happen to a twenty-five
/// minute timer; it is the ordinary thing.
@MainActor
public final class PowerCoordinator {
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var isPaused = false
    /// What every feature was reporting when the screen went away.
    ///
    /// Held in memory only, on purpose. If the app is restarted mid-absence
    /// there is no "before", and the honest outcome is to say nothing — a
    /// digest reconstructed from a total would report a whole day's data as
    /// five minutes' worth.
    private var leftAt: AwaySnapshot?

    /// Called with `true` when the island must leave the screen entirely, and
    /// `false` when it may come back. Wired by the app to the overlay window,
    /// because the coordinator deliberately knows nothing about windows.
    public var onConcealed: (Bool) -> Void = { _ in }

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context
    }

    public func begin() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })

        // Locking and unlocking are announced on the distributed centre rather
        // than the workspace one, and under names macOS has used unchanged for
        // many releases.
        let distributed = DistributedNotificationCenter.default()
        lockObservers.append(distributed.addObserver(
            forName: Notification.Name(Self.lockedNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.conceal() }
        })
        lockObservers.append(distributed.addObserver(
            forName: Notification.Name(Self.unlockedNotification), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reveal() }
        })
    }

    package static let lockedNotification = "com.apple.screenIsLocked"
    package static let unlockedNotification = "com.apple.screenIsUnlocked"

    public func end() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        lockObservers.forEach(distributed.removeObserver)
        lockObservers.removeAll()
    }

    private func pause() {
        guard !isPaused else { return }
        isPaused = true
        leftAt = snapshot()
        registry.suspendAll()
    }

    private func resume() {
        guard isPaused else { return }
        isPaused = false
        registry.resumeAll(context: context)
        report()
    }

    /// Everything the running features are willing to have compared, now.
    private func snapshot() -> AwaySnapshot {
        AwaySnapshot(at: Date(), figures: registry.runningFeatures.compactMap(\.awayFigure))
    }

    /// Work out what was missed, and hand it to whoever draws it.
    ///
    /// Taken AFTER `resumeAll`, so a feature that was put down while the screen
    /// was away has been picked up again and can answer. A feature that still
    /// cannot is simply absent from the second snapshot and drops out of the
    /// comparison rather than being guessed at.
    private func report() {
        guard let before = leftAt else { return }
        leftAt = nil
        guard let result = AwayDigest.result(from: before, to: snapshot()) else { return }
        context.away.post(line: result.line, changes: result.changes, awayFor: result.awayFor)
    }

    /// Off the screen, and everything stopped with it.
    private func conceal() {
        onConcealed(true)
        pause()
    }

    private func reveal() {
        resume()
        onConcealed(false)
    }
}
