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
/// if it only appears once you go looking. It touches neither audio nor video —
/// it reads a flag per audio process and a flag per camera.
///
/// Cheap is not the same as instant, though, and this was described as costing
/// microseconds until it was timed: 5.6 ms for the audio processes and 0.8 ms
/// for the cameras on an M2, every two seconds for as long as the app runs.
/// That is more than a whole frame at 120 Hz, so asked on the main thread it
/// was a hitch the length of a frame, twice a minute per minute, landing in the
/// middle of whatever the island was animating. It is asked off the main thread
/// and only the answer comes back to it.
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
    /// Where the system is asked, so the main thread never waits on it.
    private let queue = DispatchQueue(label: "com.hashnotch.call", qos: .utility)
    /// Whether a reading is already in flight. A machine slow enough for one
    /// read to outlast the interval should not be given a queue of them.
    private var reading = false

    /// What is asked of the system. One closure rather than two calls, so the
    /// checks can hold the rule that it is not asked on the main thread —
    /// which is the whole point of the queue above, and is otherwise the kind
    /// of thing that quietly moves back.
    private let read: @Sendable () -> (listener: CallReader.Listener?, camera: Bool)

    public init() {
        self.read = { (CallReader.current(), CameraReader.isCapturing()) }
    }

    package init(read: @escaping @Sendable () -> (listener: CallReader.Listener?, camera: Bool)) {
        self.read = read
    }

    /// Checked often enough that the dot appears as the call starts rather than
    /// some seconds into it. What it costs, and why that cost is paid off the
    /// main thread, is on the type above.
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

    /// Ask the system, away from the main thread, and bring back the answer.
    private func refresh() {
        guard !reading else { return }
        reading = true
        let read = self.read
        queue.async { [weak self] in
            let (listener, camera) = read()
            Task { @MainActor in
                guard let self else { return }
                self.reading = false
                self.apply(listener: listener, camera: camera)
            }
        }
    }

    private func apply(listener: CallReader.Listener?, camera: Bool) {
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
