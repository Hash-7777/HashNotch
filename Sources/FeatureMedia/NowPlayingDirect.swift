import Foundation

/// Reads Now Playing straight from MediaRemote, in process — where macOS lets
/// it, which on a signed app bundle it does not.
///
/// ## Measured, and the measurement was taken in the wrong place
///
/// `MRMediaRemoteGetNowPlayingInfo` returns the full dictionary INCLUDING
/// `kMRMediaRemoteNowPlayingInfoArtworkData` — 256 KB of JPEG for a YouTube
/// video, on 25 consecutive calls, worst round trip 17 ms. That was measured
/// from a plain `swift file.swift` binary and it is true of one.
///
/// It is not true of this app. Called from the signed `.app`, the same function
/// hands back a **nil dictionary**, every time. Apple gates it behind an
/// entitlement, and a command-line binary is not held to that check while a
/// bundled application is. Which is precisely why the `osascript` subprocess
/// existed in the first place: `osascript` is Apple's own binary and carries
/// what this one cannot.
///
/// So this type is, for now, a path that is tried and does not answer. It is
/// kept rather than deleted because the check costs one nil test per poll, and
/// because the entitlement rules are Apple's to change — if a future macOS
/// answers, everything below starts working with no further edit. What it must
/// NOT be is a claim: nothing in the app's documentation may promise artwork
/// for every player, because on a shipped build this never runs.
///
/// The lesson is the one already written into CONTRIBUTING, and it caught me
/// anyway: measure the thing you are going to ship, in the form you are going
/// to ship it. A standalone binary is a different program.
///
/// Read-only throughout: this asks what is playing and never sets anything.
package final class NowPlayingDirect {
    /// One track, as MediaRemote describes it.
    package struct Snapshot {
        package let title: String
        package let artist: String?
        package var isPlaying: Bool
        /// Whether the dictionary carried a playback rate at all. A missing
        /// rate is not a rate of zero — see `read(on:completion:)`.
        package let rateReported: Bool
        /// Where the track was at `elapsedAt` — the player's own figure, not a
        /// position worked out from it.
        package let elapsed: Double?
        /// When that figure was true. Everything downstream derives the current
        /// position from this pair and nothing else.
        package let elapsedAt: Date
        package let duration: Double?
        package let artwork: Data?
        /// The bundle id of the app that is playing, when the system says.
        /// Used only to pick a control channel — never to decide whether a
        /// track is worth showing, so an app nobody has heard of still works.
        package let bundleIdentifier: String?
    }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias SetElapsedFn = @convention(c) (Double) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias ClientBundleFn = @convention(c) (AnyObject?) -> Unmanaged<CFString>?
    private typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private let getInfo: GetInfoFn
    private let setElapsed: SetElapsedFn?
    private let getClient: GetClientFn?
    private let clientBundle: ClientBundleFn?
    private let appIsPlaying: IsPlayingFn?

    /// Nil when MediaRemote is not where it is expected, or does not export the
    /// call. Every use site treats that as "fall back", never as a failure.
    init?() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else { return nil }
        getInfo = unsafeBitCast(symbol, to: GetInfoFn.self)
        setElapsed = dlsym(handle, "MRMediaRemoteSetElapsedTime")
            .map { unsafeBitCast($0, to: SetElapsedFn.self) }
        getClient = dlsym(handle, "MRMediaRemoteGetNowPlayingClient")
            .map { unsafeBitCast($0, to: GetClientFn.self) }
        clientBundle = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier")
            .map { unsafeBitCast($0, to: ClientBundleFn.self) }
        appIsPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            .map { unsafeBitCast($0, to: IsPlayingFn.self) }
    }

    /// Asks which app is playing. Answers with nil rather than failing.
    ///
    /// Used ONLY to choose how a command is sent — Spotify and Music need their
    /// own scripting to resume reliably, everything else does not have any. It
    /// deliberately has no say in whether a track is shown, so an app nobody
    /// has ever heard of appears on the notch exactly like a known one.
    func readOwner(on queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        guard let getClient, let clientBundle else { completion(nil); return }
        getClient(queue) { client in
            guard let client else { completion(nil); return }
            completion(clientBundle(client)?.takeUnretainedValue() as String?)
        }
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    /// Whether this build of macOS will let us move the playhead.
    var canSeek: Bool { setElapsed != nil }

    /// The largest cover the app will hold. The system hands these over
    /// directly, so nothing is downloaded — but a bound still belongs here,
    /// because this data is decoded into an image on the main thread.
    package static let maxArtworkBytes = 8_000_000

    /// Reads the current track. The completion runs on `queue`.
    ///
    /// Never blocks: this is the callback form of the API, so a slow or absent
    /// answer costs nothing. A caller that gets nil should try the fallback.
    ///
    /// A dictionary with no playback rate at all is asked one more question:
    /// whether the system considers the playing app to be playing. A player can
    /// leave the rate out while it plays, and reading that as paused hid a song
    /// that had just started, since a paused track at 0:00 has not earned a
    /// place on the notch.
    func read(on queue: DispatchQueue, completion: @escaping (Snapshot?) -> Void) {
        let appIsPlaying = self.appIsPlaying
        getInfo(queue) { info in
            guard let info, var snapshot = Self.snapshot(from: info) else { completion(nil); return }
            guard !snapshot.rateReported, let appIsPlaying else { completion(snapshot); return }
            appIsPlaying(queue) { playing in
                snapshot.isPlaying = playing
                completion(snapshot)
            }
        }
    }

    /// Turns MediaRemote's dictionary into a snapshot, or nil if there is no
    /// track worth showing.
    ///
    /// Package-visible and pure so the checks can pin the parsing — including
    /// the cases that matter and cannot be staged on demand: a dictionary with
    /// no title, an oversized cover, a negative duration.
    package static func snapshot(from info: [String: Any], now: Date = Date()) -> Snapshot? {
        func string(_ key: String) -> String? {
            (info["kMRMediaRemoteNowPlayingInfo" + key] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        func number(_ key: String) -> Double? {
            (info["kMRMediaRemoteNowPlayingInfo" + key] as? NSNumber)?.doubleValue
        }

        // No title, nothing to show. Every other field is optional garnish.
        guard let title = string("Title") else { return nil }

        let artwork = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
            .flatMap { $0.isEmpty || $0.count > maxArtworkBytes ? nil : $0 }

        // A duration of zero is what a live stream reports, and dividing a
        // progress bar by it produces either a crash or a full bar. Treated as
        // "no duration", which the panel already knows how to draw.
        let duration = number("Duration").flatMap { $0 > 0 ? $0 : nil }
        let rate = number("PlaybackRate")
        let isPlaying = (rate ?? 0) > 0

        // The player's own pair, handed on untouched: where the track was, and
        // WHEN it was there. Both, together, or neither is any use.
        //
        // `ElapsedTime` alone is not the position now — macOS refreshes it only
        // when something happens, so on an undisturbed track it falls behind by
        // however long nobody has touched it (measured once at 217 seconds).
        // The timestamp beside it is what makes it meaningful.
        //
        // This used to work the position out here, and then the monitor kept a
        // clock of its own and worked it out AGAIN from a different starting
        // instant. Two extrapolations of one truth, from two reference points,
        // arbitrated by a rule about which to believe — which is why the
        // readout could sit there counting 1, 2, 3, 1, 2, 3. Nothing is
        // computed here now. The pair travels to the one place that needs a
        // number, and the position is derived once, at the moment of drawing.
        let elapsed = number("ElapsedTime").map { max(0, $0) }
        let elapsedAt = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date

        return Snapshot(
            title: title,
            artist: string("Artist"),
            isPlaying: isPlaying,
            rateReported: rate != nil,
            elapsed: elapsed,
            elapsedAt: elapsedAt ?? now,
            duration: duration,
            artwork: artwork,
            bundleIdentifier: nil
        )
    }

    /// Which control channel an app answers to.
    ///
    /// The only place a bundle id is matched by name, and it is worth being
    /// clear about why that is not the thing the app was asked to stop doing.
    /// Recognising apps in order to DISPLAY them would mean anything unlisted
    /// gets nothing — which is what used to happen, and why Anghami or TV drew
    /// a placeholder. Nothing here affects display: every app is read, shown
    /// and given artwork identically. This picks how a *command* is delivered,
    /// and that genuinely differs — Spotify and Music release the now-playing
    /// session when paused, so only their own scripting can resume them, while
    /// everything else has no scripting interface to prefer.
    ///
    /// An app that is not listed is not unsupported; it takes the same route as
    /// every other app, which is the route that suits it.
    package static func source(forBundleIdentifier bundle: String?) -> MediaSource {
        switch bundle?.lowercased() {
        case "com.spotify.client": return .spotify
        case "com.apple.music", "com.apple.itunes": return .music
        default: return .other
        }
    }

    /// Moves the playhead. Only offered when the symbol exists.
    func seek(to seconds: Double) {
        setElapsed?(max(0, seconds))
    }
}
