import AppKit
import Combine
import Foundation
import HashNotchKit

/// A microphone that is open, and for how long.
public struct MicrophoneUse: Equatable {
    public let appName: String
    public let bundleIdentifier: String
    /// False when nothing could be honestly attributed to an app, so the
    /// readout says a microphone is in use rather than naming a daemon.
    public let isNamedApp: Bool
    /// When the microphone was first seen open. Not necessarily when a call was
    /// answered — nothing available here knows that.
    public let since: Date

    public func elapsed(now: Date) -> TimeInterval { now.timeIntervalSince(since) }
}

/// Watches for an app opening the microphone, and times it.
///
/// This is the one feature that runs while the panel is SHUT, and it earns that
/// deliberately: a dot saying your microphone is live is worth nothing if it
/// only appears once you go looking. It is also close to free — reading a
/// boolean per audio process costs microseconds and touches no audio at all.
///
/// It never listens. See `CallReader` for exactly what is asked of the system
/// and why that is not the same as using a microphone.
@MainActor
public final class CallMonitor: ObservableObject {
    @Published public private(set) var use: MicrophoneUse?
    /// Ticks while a call is running so the duration counts up.
    @Published public private(set) var now = Date()

    private var sampler: PollingSampler?
    private var ticker: PollingSampler?
    private weak var presence: LivePresence?

    public init() {}

    /// Checked often enough that the dot appears as the call starts rather than
    /// some seconds into it, and cheap enough that doing so costs nothing —
    /// this reads a flag per audio process, it does not open audio.
    private nonisolated static let watchInterval: TimeInterval = 2

    public func start(presence: LivePresence) {
        self.presence = presence
        let sampler = PollingSampler(interval: Self.watchInterval) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.sampler = sampler
        sampler.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        stopTicking()
        use = nil
        presence?.setActive("call", false)
    }

    private func refresh() {
        guard let listener = CallReader.current() else {
            if use != nil {
                use = nil
                stopTicking()
                presence?.setActive("call", false)
            }
            return
        }

        // The same app still holding the microphone is the same call — keep the
        // clock running rather than restarting it.
        if let existing = use, existing.bundleIdentifier == listener.bundleIdentifier {
            return
        }

        use = MicrophoneUse(
            appName: listener.name,
            bundleIdentifier: listener.bundleIdentifier,
            isNamedApp: listener.isNamedApp,
            since: Date()
        )
        presence?.setActive("call", true)
        startTicking()
    }

    /// The duration only needs a clock while it is on screen, and only to the
    /// second.
    private func startTicking() {
        guard ticker == nil else { return }
        now = Date()
        let ticker = PollingSampler(interval: 1) { [weak self] in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        self.ticker = ticker
        ticker.start()
    }

    private func stopTicking() {
        ticker?.stop()
        ticker = nil
    }

    /// The app's own icon, so a call shows the thing it is in rather than a
    /// generic symbol. Read from the running application — no file is opened
    /// and nothing is downloaded.
    public func appIcon() -> NSImage? {
        guard let use, use.isNamedApp else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: use.bundleIdentifier)
            .first?.icon
    }
}
