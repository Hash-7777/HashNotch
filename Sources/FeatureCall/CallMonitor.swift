import AppKit
import Combine
import Foundation
import HashNotchKit

/// A microphone or a camera that is open, and for how long.
///
/// One reading rather than two, deliberately. Something using both — which is
/// every video call — is one thing happening, and saying it twice would be two
/// rows about one meeting. Something using only the camera is the same reading
/// with the other half switched off.
public struct MicrophoneOrCameraUse: Equatable {
    public let appName: String
    public let bundleIdentifier: String
    /// False when nothing could be honestly attributed to an app, so the readout
    /// says what is in use rather than naming a daemon — or, for a camera on its
    /// own, names nothing at all, because nothing can name it.
    public let isNamedApp: Bool
    /// Which of the two is live. Both can be, and either can be alone.
    public let microphone: Bool
    public let camera: Bool
    /// When this was first seen open. Not necessarily when a call was answered —
    /// nothing available here knows that.
    public let since: Date

    /// Spelled out rather than left to the compiler, so the checks can build a
    /// reading — a camera and a microphone held at once cannot be staged inside
    /// a check, and the shape of the reading is worth pinning anyway.
    public init(
        appName: String,
        bundleIdentifier: String,
        isNamedApp: Bool,
        microphone: Bool,
        camera: Bool,
        since: Date
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.isNamedApp = isNamedApp
        self.microphone = microphone
        self.camera = camera
        self.since = since
    }

    public func elapsed(now: Date) -> TimeInterval { now.timeIntervalSince(since) }
}

/// Watches for an app opening the microphone or a camera, and times it.
///
/// This is the one feature that runs while the panel is SHUT, and it earns that
/// deliberately: a dot saying your microphone or camera is live is worth nothing
/// if it only appears once you go looking. It is also close to free — a boolean
/// per audio process and a boolean per camera costs microseconds and touches
/// neither audio nor video.
///
/// It never listens and never watches. See `CallReader` and `CameraReader` for
/// exactly what is asked of the system, and why neither is the same as using the
/// thing being asked about.
@MainActor
public final class CallMonitor: ObservableObject {
    @Published public private(set) var use: MicrophoneOrCameraUse?
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
        let listener = CallReader.current()
        let camera = CameraReader.isCapturing()
        let microphone = listener != nil

        guard microphone || camera else {
            if use != nil {
                use = nil
                stopTicking()
                presence?.setActive("call", false)
            }
            return
        }

        // Who it is, when that can be answered. The microphone can name an app;
        // the camera cannot, because CoreMediaIO publishes no list of processes
        // to ask. A camera on its own is therefore reported as live and unnamed
        // rather than attributed to whichever app seems likely — naming the
        // wrong app on a row about being watched is worse than naming none.
        let name: String
        let bundle: String
        let isNamed: Bool
        if let listener {
            name = listener.isNamedApp
                ? listener.name
                : CallReader.unattributedName(microphone: true, camera: camera)
            bundle = listener.bundleIdentifier
            isNamed = listener.isNamedApp
        } else {
            name = CallReader.unattributedName(microphone: false, camera: true)
            bundle = ""
            isNamed = false
        }

        // Still the same thing happening? Then keep the clock and only update
        // which half is live. Muting yourself mid-call takes the microphone —
        // and the app's name with it — and leaves a camera nobody can attribute;
        // restarting the timer there would say the call had ended.
        if let existing = use,
           CallReader.isSameSession(
               previousBundle: existing.bundleIdentifier,
               previousIsNamed: existing.isNamedApp,
               bundle: bundle,
               isNamed: isNamed
           ) {
            guard existing.microphone != microphone
                    || existing.camera != camera
                    || existing.appName != name
                    || existing.bundleIdentifier != bundle
            else { return }
            use = MicrophoneOrCameraUse(
                appName: name,
                bundleIdentifier: bundle,
                isNamedApp: isNamed,
                microphone: microphone,
                camera: camera,
                since: existing.since
            )
            return
        }

        use = MicrophoneOrCameraUse(
            appName: name,
            bundleIdentifier: bundle,
            isNamedApp: isNamed,
            microphone: microphone,
            camera: camera,
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
