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
/// taken off screen and every feature is stopped, so there is nothing to be
/// covered and nothing being read while the Mac is locked.
@MainActor
public final class PowerCoordinator {
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var isPaused = false

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
        registry.stopAll()
    }

    private func resume() {
        guard isPaused else { return }
        isPaused = false
        registry.syncRunning(context: context)
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
