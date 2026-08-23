import Foundation
import SwiftUI
import CoreGraphics
import AppKit
import HashNotchKit
import FeatureMedia
import FeatureActivities
import FeatureTokens
import FeatureBattery
import FeatureDownloads
import FeatureAirPods
import FeatureCall
import FeatureNetwork
import FeatureThermal
import FeatureStorage
import FeatureCPU
import FeatureMemory

/// Writes `content` to a fresh temp file and returns its URL.
func tempFile(_ content: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-check-\(UUID().uuidString).json")
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// A tiny, dependency-free check runner. Prints one line per check and exits
// non-zero if any fails, so it works as a pre-push gate under the Command Line
// Tools alone (no XCTest / Swift Testing needed).

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  ok   \(name)")
    } else {
        print("  FAIL \(name)")
        failures += 1
    }
}

/// A `UserDefaults` that never touches the preferences system.
///
/// The checks used to run against real, named suites — `UserDefaults(suiteName:)`
/// — and clean them up afterwards. That cannot be made to work, and finding out
/// took measuring three different ways of doing it.
///
/// Preferences are not written by this process. `cfprefsd` owns them, holds each
/// domain it has been asked about in memory, and writes it out on its own
/// schedule. Emptying the domain, telling `cfprefsd` to synchronise it, removing
/// the suite, and deleting the file — in every order, all of it — still leaves a
/// 42-byte empty plist in ~/Library/Preferences a minute after this process has
/// exited, because the domain is one `cfprefsd` has seen and it writes an empty
/// representation when it next flushes. Nothing done from in here survives the
/// exit, so the cleanup was never a cleanup: it was a head start on a race that
/// was always lost after anybody stopped looking.
///
/// So the checks no longer create a preference domain at all. Every throwaway
/// store is one of these: the same API, backed by a dictionary, gone when the
/// process is. There is nothing to sweep, which is a stronger claim than
/// sweeping it well.
///
/// What is given up is proof that a document survives a round trip through the
/// real defaults system. That is Apple's code rather than this project's, and it
/// was never what these checks were about — they are about what `SettingsStore`
/// does with what it reads back, and it reads back through exactly this API.
///
/// Only the three accessors everything here actually uses are overridden, which
/// is the documented way to subclass this: the typed readers (`data(forKey:)`
/// and friends) are defined in terms of `object(forKey:)`, so they follow.
final class InMemoryDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { storage[key] }

    override func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    override func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
}

/// The prefix the checks' throwaway domains used to carry, kept only so the
/// sweep at the end can clear up after an older build that still made them.
let checkDomainPrefix = "hashnotch.checks."

/// A throwaway feature — proves the core is decoupled from concrete features.
@MainActor
private final class StubFeature: NotchFeature {
    let id: String
    let title: String
    let placement: FeaturePlacement
    init(id: String, placement: FeaturePlacement) {
        self.id = id
        self.title = id
        self.placement = placement
    }
    func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }
}

/// A stub that remembers whether it is running, so the checks can tell apart a
/// feature that is hidden from one that has actually been stopped.
@MainActor
private final class CountingFeature: NotchFeature {
    let id: String
    let title: String
    let placement: FeaturePlacement = .expanded
    private(set) var isRunning = false
    private(set) var starts = 0
    /// Whether this stub will claim a sideways swipe, and what it last saw.
    var claimsSwipes = false
    private(set) var swipes: [SwipeDirection] = []

    init(id: String) {
        self.id = id
        self.title = id
    }

    func start(context: FeatureContext) {
        isRunning = true
        starts += 1
    }
    func stop() { isRunning = false }
    func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }

    func handleSwipe(_ direction: SwipeDirection) -> Bool {
        guard claimsSwipes else { return false }
        swipes.append(direction)
        return true
    }
}

MainActor.assumeIsolated {
    print("HashNotch core checks")

    // Registry keeps registration order.
    let ordered = FeatureRegistry()
    ordered.register([
        StubFeature(id: "a", placement: .leading),
        StubFeature(id: "b", placement: .trailing),
        StubFeature(id: "c", placement: .leading),
    ])
    check("registry keeps order", ordered.features.map(\.id) == ["a", "b", "c"])

    // Registry filters by placement.
    check("filter leading", ordered.features(for: .leading).map(\.id) == ["a", "c"])
    check("filter trailing", ordered.features(for: .trailing).map(\.id) == ["b"])
    check("filter expanded empty", ordered.features(for: .expanded).isEmpty)

    // Switching a feature off stops it, rather than merely hiding it. This is a
    // privacy promise as much as a battery one: a feature that is off must not
    // still be listing your Downloads folder or asking your browser what it is
    // playing.
    let runDefaults = InMemoryDefaults()
    let runSettings = checkStore(defaults: runDefaults)
    let onFeature = CountingFeature(id: "on")
    let offFeature = CountingFeature(id: "off")
    let runRegistry = FeatureRegistry()
    runRegistry.register([onFeature, offFeature])
    runSettings.seed(features: runRegistry.features)
    runSettings.update("off") { $0.enabled = false }

    let runContext = FeatureContext(settings: runSettings)
    runRegistry.syncRunning(context: runContext)
    check("a feature that is on is started", onFeature.isRunning)
    check("a feature that is off is never started", offFeature.isRunning == false)
    check("only the running feature is tracked", runRegistry.runningIDs == ["on"])

    // Flipping a switch takes effect on the feature itself, both ways.
    runSettings.update("off") { $0.enabled = true }
    runRegistry.syncRunning(context: runContext)
    check("switching a feature on starts it", offFeature.isRunning)

    runSettings.update("on") { $0.enabled = false }
    runRegistry.syncRunning(context: runContext)
    check("switching a feature off stops it", onFeature.isRunning == false)
    check("the other feature is left alone", offFeature.isRunning)

    // Settings publish on every change, including reorders and style changes,
    // so the sync must be free to run often without restarting anything.
    let startsBefore = offFeature.starts
    runRegistry.syncRunning(context: runContext)
    runRegistry.syncRunning(context: runContext)
    check("syncing again does not restart a running feature", offFeature.starts == startsBefore)

    // Nothing reads anything until somebody has been asked.
    //
    // Every switch above was already honoured, but they all ship ON, so a
    // first launch listed the Downloads folder and asked macOS which processes
    // held the microphone BEFORE offering the switches. Being able to turn
    // something off afterwards is not the same as having been asked. These pin
    // the state before consent as the everything-off state itself, rather than
    // a promise about it.
    let gateSettings = checkStore(defaults: InMemoryDefaults(), accepted: false)
    let gatedFeature = CountingFeature(id: "gated")
    let gateRegistry = FeatureRegistry()
    gateRegistry.register([gatedFeature])
    gateSettings.seed(features: gateRegistry.features)
    let gateContext = FeatureContext(settings: gateSettings)

    check("a fresh install has agreed to nothing", gateSettings.hasAcceptedReading == false)
    check("the feature is switched on all the same", gateSettings.isEnabled("gated"))
    gateRegistry.syncRunning(context: gateContext)
    check("yet nothing starts before the reading is agreed to", gatedFeature.isRunning == false)
    check("and nothing is tracked as running either", gateRegistry.runningIDs.isEmpty)

    // Agreeing is what starts it, and it starts what was switched on.
    gateSettings.hasAcceptedReading = true
    gateRegistry.syncRunning(context: gateContext)
    check("agreeing starts what is switched on", gatedFeature.isRunning)

    // Withdrawing stops everything again, so the gate is a real switch rather
    // than a one-way door that only ever gets opened.
    gateSettings.hasAcceptedReading = false
    gateRegistry.syncRunning(context: gateContext)
    check("withdrawing stops it reading again", gatedFeature.isRunning == false)

    // A sideways swipe over the open panel is offered to the features until one
    // takes it. The core stays ignorant of what the gesture means — it only
    // knows the fingers went sideways over the panel.
    let swipeSettings = checkStore(defaults: InMemoryDefaults())
    let quietFeature = CountingFeature(id: "quiet")
    let eagerFeature = CountingFeature(id: "eager")
    let laterFeature = CountingFeature(id: "later")
    let swipeRegistry = FeatureRegistry()
    swipeRegistry.register([quietFeature, eagerFeature, laterFeature])
    swipeSettings.seed(features: swipeRegistry.features)
    let swipeContext = FeatureContext(settings: swipeSettings)
    swipeRegistry.syncRunning(context: swipeContext)

    // Which way the fingers went. Wrong first time, and nothing could have
    // caught it: the gesture fired and the panel responded, it just skipped the
    // opposite way. The vertical rule is `inverted ? delta > 0 : delta < 0` for
    // fingers-down and the axes do not mirror — with natural scrolling the
    // content follows the fingers, so fingers-down is a POSITIVE deltaY while
    // fingers-left is a NEGATIVE deltaX.
    check(
        "with natural scrolling, fingers left is a leftward swipe",
        NotchWindowController.swipeDirection(acrossDelta: -30, naturalScrolling: true) == .left
    )
    check(
        "with natural scrolling, fingers right is a rightward swipe",
        NotchWindowController.swipeDirection(acrossDelta: 30, naturalScrolling: true) == .right
    )
    check(
        "with natural scrolling off, the sign is the other way round",
        NotchWindowController.swipeDirection(acrossDelta: 30, naturalScrolling: false) == .left
            && NotchWindowController.swipeDirection(acrossDelta: -30, naturalScrolling: false) == .right
    )
    // The two settings must never agree about the same physical movement, or
    // one of them is reading the trackpad backwards.
    check(
        "the two scrolling settings never read a movement the same way",
        NotchWindowController.swipeDirection(acrossDelta: 30, naturalScrolling: true)
            != NotchWindowController.swipeDirection(acrossDelta: 30, naturalScrolling: false)
    )

    check("a swipe nobody wants is simply ignored", swipeRegistry.handleSwipe(.left) == false)

    eagerFeature.claimsSwipes = true
    laterFeature.claimsSwipes = true
    check("a swipe reaches the feature that wants it", swipeRegistry.handleSwipe(.left))
    check("the direction survives the trip", eagerFeature.swipes == [.left])
    // Two features both willing to act would otherwise skip two tracks, or skip
    // one and do something else, from a single flick.
    check("only the first claimer acts on one swipe", laterFeature.swipes.isEmpty)
    check("a feature that does not claim swipes is unaffected", quietFeature.swipes.isEmpty)

    swipeRegistry.handleSwipe(.right)
    check("the other direction arrives too", eagerFeature.swipes == [.left, .right])

    // A feature the user switched off is stopped, not merely hidden. A gesture
    // must not be a back door into something that was turned off.
    swipeSettings.update("eager") { $0.enabled = false }
    swipeRegistry.syncRunning(context: swipeContext)
    let beforeOff = eagerFeature.swipes.count
    check("a switched-off feature is never offered the swipe", swipeRegistry.handleSwipe(.left))
    check("and it did not act", eagerFeature.swipes.count == beforeOff)
    check("the swipe fell through to the next running feature", laterFeature.swipes == [.left])

    runRegistry.stopAll()
    check("stopping everything clears what is running", runRegistry.runningIDs.isEmpty)

    // The draw order is cached against a generation counter, because the island
    // asks for it while it is drawing. A cache that answered with a stale list
    // would be worse than the sort it replaced: a feature switched off would
    // keep drawing, and a reorder would not land until something else happened
    // to change. So the thing actually pinned here is that it INVALIDATES.
    let orderDefaults = InMemoryDefaults()
    let orderSettings = checkStore(defaults: orderDefaults)
    let orderRegistry = FeatureRegistry()
    orderRegistry.register([
        StubFeature(id: "first", placement: .expanded),
        StubFeature(id: "second", placement: .expanded),
        StubFeature(id: "third", placement: .expanded),
    ])
    orderSettings.seed(features: orderRegistry.features)

    check(
        "the draw order starts as the registration order",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id) == ["first", "second", "third"]
    )
    check(
        "asking twice gives the same answer",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id)
            == orderRegistry.orderedEnabled(using: orderSettings).map(\.id)
    )

    orderSettings.setOrder(["third", "first", "second"])
    check(
        "reordering reaches the draw order rather than a stale cache",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id) == ["third", "first", "second"]
    )

    orderSettings.update("first") { $0.enabled = false }
    check(
        "a feature switched off leaves the draw order",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id) == ["third", "second"]
    )

    orderSettings.update("first") { $0.enabled = true }
    check(
        "switching it back on returns it to its place",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id) == ["third", "first", "second"]
    )

    // Two features can only share an order if a saved document predates seed(),
    // and Array.sorted is not stable — so without an explicit tiebreak the pair
    // could swap places between one redraw and the next.
    orderSettings.update("first") { $0.order = 0 }
    orderSettings.update("second") { $0.order = 0 }
    orderSettings.update("third") { $0.order = 0 }
    check(
        "features sharing an order fall back to a fixed sequence, never to chance",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id) == ["first", "second", "third"]
    )

    // Registering after the cache is warm must not hand back the old list.
    orderRegistry.register(StubFeature(id: "late", placement: .expanded))
    orderSettings.seed(features: orderRegistry.features)
    check(
        "a feature registered later still reaches the draw order",
        orderRegistry.orderedEnabled(using: orderSettings).map(\.id).contains("late")
    )

    // Only one feature may own the live strip. Two of them at once is what put
    // "Claude finished" on top of the song title: the pill grew past the width
    // its own centring is derived from and slid across the notch.
    func stripOwner(_ candidates: [(id: String, priority: Int)], live: Set<String>) -> String? {
        var best: (id: String, priority: Int, index: Int)?
        for (index, candidate) in candidates.enumerated() where live.contains(candidate.id) {
            if let current = best,
               candidate.priority < current.priority
                || (candidate.priority == current.priority && index > current.index) {
                continue
            }
            best = (candidate.id, candidate.priority, index)
        }
        return best?.id
    }

    let strip = [
        (id: "media", priority: LivePriority.ongoing),
        (id: "timer", priority: LivePriority.ongoing),
        (id: "downloads", priority: LivePriority.announcement),
        (id: "activities", priority: LivePriority.needsYou),
    ]
    check("nothing live means nothing on the strip", stripOwner(strip, live: []) == nil)
    check("one live feature owns it", stripOwner(strip, live: ["media"]) == "media")
    check(
        "a finished job takes the strip from the music",
        stripOwner(strip, live: ["media", "activities"]) == "activities"
    )
    check(
        "a battery notice outranks a playing track",
        stripOwner(strip, live: ["media", "downloads"]) == "downloads"
    )
    check(
        "something waiting on you outranks a passing notice",
        stripOwner(strip, live: ["downloads", "activities"]) == "activities"
    )
    check(
        "equal priority falls back to registration order, never to chance",
        stripOwner(strip, live: ["timer", "media"]) == "media"
    )
    check(
        "the strip returns to the music once the notice leaves",
        stripOwner(strip, live: ["media"]) == "media"
    )
    check("an announcement outranks something merely ongoing", LivePriority.announcement > LivePriority.ongoing)
    check("waiting on you outranks an announcement", LivePriority.needsYou > LivePriority.announcement)

    // Island sizing: collapsed matches the notch, expanded is larger.
    let state = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32),
        hasNotch: true
    ))
    check("notch width", state.notchWidth == 200)
    check("collapsed matches notch", state.collapsedWidth == 200)
    check("expanded is larger", state.expandedWidth > state.collapsedWidth && state.expandedHeight > state.collapsedHeight)

    // The black is exactly the hardware in BOTH states, so nothing of this app's
    // ever hangs below the notch onto the wallpaper. What the live strip adds is
    // transparent clearance for the coloured line, which is drawn just outside
    // the pill's bottom edge rather than centred on it — centred would put half
    // its width behind the hardware, which is the half that never lights up.
    check("the idle shape is exactly the notch", state.collapsedHeight == state.notchHeight)
    check("and so is the live strip's black", state.collapsedHeight == state.notchHeight)
    check("the window keeps a little room below it for the line",
          state.liveHeight == state.notchHeight + NotchState.liveLip)
    check("and it is room for a line, not for more black",
          NotchState.liveLip > 0 && NotchState.liveLip <= 2)

    // Rate formatter scales units.
    check("rate B", Formatters.rate(512).unit == "B/s")
    check("rate KB", Formatters.rate(9_216).value == "9" && Formatters.rate(9_216).unit == "KB/s")
    check("rate MB", Formatters.rate(5_242_880).unit == "MB/s")

    // Network readout is always MB/s with two decimals (fixed layout).
    check("mbps unit fixed", Formatters.megabytesUnit == "MB/s")
    check("mbps small", Formatters.megabytesPerSecond(12_288) == "0.01")
    check("mbps whole", Formatters.megabytesPerSecond(5_242_880) == "5.00")

    // Battery time-remaining reads as explicit hours/minutes, never a clock.
    check("hm minutes only", Formatters.hoursMinutes(45) == "45m")
    check("hm hours and minutes", Formatters.hoursMinutes(154) == "2h 34m")
    check("hm whole hours", Formatters.hoursMinutes(180) == "3h")
    check("hm under an hour zero-safe", Formatters.hoursMinutes(0) == "0m")

    // Compact token counts.
    check("count small", Formatters.compactCount(812) == "812")
    check("count K", Formatters.compactCount(12_300) == "12.3K")
    check("count M", Formatters.compactCount(4_500_000) == "4.5M")
    check("count B", Formatters.compactCount(1_280_000_000) == "1.28B")

    // Artwork downloads: HTTPS to Spotify's own CDN only — the app's single
    // network access must never fetch an arbitrary or non-HTTPS URL.
    check("artwork allows Spotify CDN", ArtworkPolicy.isTrustedURL("https://i.scdn.co/image/abc123"))
    check("artwork allows Spotify CDN alt", ArtworkPolicy.isTrustedURL("https://images.spotifycdn.com/x.jpg"))
    check("artwork allows YouTube thumbs", ArtworkPolicy.isTrustedURL("https://i.ytimg.com/vi/abc123/hqdefault.jpg"))
    check("artwork refuses ytimg lookalike", !ArtworkPolicy.isTrustedURL("https://evilytimg.com/vi/abc123/x.jpg"))
    check("artwork refuses http", !ArtworkPolicy.isTrustedURL("http://i.scdn.co/image/abc123"))
    check("artwork refuses other hosts", !ArtworkPolicy.isTrustedURL("https://example.com/a.jpg"))
    check("artwork refuses lookalike host", !ArtworkPolicy.isTrustedURL("https://evilscdn.co/a.jpg"))
    check("artwork refuses file scheme", !ArtworkPolicy.isTrustedURL("file:///etc/passwd"))
    check("artwork refuses garbage", !ArtworkPolicy.isTrustedURL("not a url"))
    // Withdrawn, and pinned as withdrawn. Anghami's covers were reachable but
    // the identifier they hang on does not keep step with the track, so the
    // picture shown was often the previous song's. Nothing may fetch from that
    // host again without this check being deliberately deleted.
    check("artwork refuses Anghami's host", !ArtworkPolicy.isTrustedURL("https://artwork.anghcdn.co/webp/?id=123&size=320"))

    // Each service is switchable on its own, and the switch has to reach the
    // NETWORK, not just the window. A host stays refused while its service is
    // off, and turning one off must not touch the others — that is the whole
    // point of them being separate permissions to separate companies.
    do {
        let everything = ArtworkPolicy.enabledServices()
        ArtworkPolicy.setEnabledServices(everything.subtracting([ArtworkService.youtube.id]))
        check(
            "a service switched off is refused",
            !ArtworkPolicy.isTrustedURL("https://i.ytimg.com/vi/abc/hqdefault.jpg")
        )
        check(
            "switching one off leaves the others alone",
            ArtworkPolicy.isTrustedURL("https://i.scdn.co/image/abc123")
        )
        ArtworkPolicy.setEnabledServices([])
        check(
            "with every service off nothing is fetched at all",
            ArtworkService.all.allSatisfy { service in
                service.hosts.allSatisfy { !ArtworkPolicy.isTrustedURL("https://\($0)/x.jpg") }
            }
        )
        ArtworkPolicy.setEnabledServices(everything)
        check("switching them back on restores the allowlist", ArtworkPolicy.isTrustedURL("https://i.scdn.co/image/abc123"))
    }

    // A host nobody claims has no service, which is what makes "refused" the
    // default rather than something each new host has to be added to.
    check("an unclaimed host belongs to no service", ArtworkPolicy.service(forURL: "https://example.com/a.jpg") == nil)
    check("YouTube's host is YouTube's", ArtworkPolicy.service(forURL: "https://i.ytimg.com/x")?.id == ArtworkService.youtube.id)
    check(
        "every service id is distinct",
        Set(ArtworkService.all.map(\.id)).count == ArtworkService.all.count
    )

    // Playback commands. Play and pause are separate on purpose: a toggle sent
    // to a player that has released the now-playing session is accepted,
    // reported as successful, and ignored — which is exactly how a paused track
    // used to refuse to resume. Pinning the mapping here means the two can
    // never be swapped silently.
    check("play scripts as play", MediaCommand.play.scriptVerb == "play")
    check("pause scripts as pause", MediaCommand.pause.scriptVerb == "pause")
    check("next scripts as next track", MediaCommand.next.scriptVerb == "next track")
    check(
        "previous scripts as previous track",
        MediaCommand.previous.scriptVerb == "previous track"
    )
    check("play is remote code 0", MediaCommand.play.remoteCode == 0)
    check("pause is remote code 1", MediaCommand.pause.remoteCode == 1)
    check("next is remote code 4", MediaCommand.next.remoteCode == 4)
    check("previous is remote code 5", MediaCommand.previous.remoteCode == 5)
    check(
        "no command is ever a toggle",
        ![MediaCommand.play, .pause, .next, .previous]
            .contains { $0.remoteCode == 2 }
    )

    // A player takes a beat to obey a command. Inside that beat the button
    // keeps what it showed; outside it the player is always right.
    func settles(_ since: TimeInterval, _ polled: Bool, _ optimistic: Bool) -> Bool {
        MediaMonitor.keepsOptimisticPlayState(
            secondsSinceCommand: since,
            window: 1.5,
            polledIsPlaying: polled,
            optimisticIsPlaying: optimistic
        )
    }
    check("a stale poll right after pressing play is ignored", settles(0.2, false, true))
    check("a stale poll right after pressing pause is ignored", settles(0.2, true, false))
    check("an agreeing poll is never overridden", settles(0.2, true, true) == false)
    check("the player wins once the window has passed", settles(2.0, false, true) == false)
    check("the window is exclusive at its edge", settles(1.5, false, true) == false)

    // Reading Now Playing straight from MediaRemote, artwork and all. This is
    // what lets any app work — Anghami, TV, Podcasts, VLC — rather than only
    // the three the old subprocess knew how to scrape covers from.
    func mediaInfo(
        title: String? = "Night Drive",
        artist: String? = "HASH",
        rate: Double? = 1,
        elapsed: Double? = 12,
        duration: Double? = 240,
        artwork: Data? = Data([0xFF, 0xD8, 0xFF])
    ) -> [String: Any] {
        var info: [String: Any] = [:]
        if let title { info["kMRMediaRemoteNowPlayingInfoTitle"] = title }
        if let artist { info["kMRMediaRemoteNowPlayingInfoArtist"] = artist }
        if let rate { info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = NSNumber(value: rate) }
        if let elapsed { info["kMRMediaRemoteNowPlayingInfoElapsedTime"] = NSNumber(value: elapsed) }
        if let duration { info["kMRMediaRemoteNowPlayingInfoDuration"] = NSNumber(value: duration) }
        if let artwork { info["kMRMediaRemoteNowPlayingInfoArtworkData"] = artwork }
        return info
    }

    check("a track reads back from the system's own dictionary", {
        guard let s = NowPlayingDirect.snapshot(from: mediaInfo()) else { return false }
        return s.title == "Night Drive" && s.artist == "HASH" && s.isPlaying
            && s.elapsed == 12 && s.duration == 240 && s.artwork?.count == 3
    }())
    check(
        "a dictionary with no title is not a track",
        NowPlayingDirect.snapshot(from: mediaInfo(title: nil)) == nil
    )
    check(
        "an empty title is not a title",
        NowPlayingDirect.snapshot(from: mediaInfo(title: "")) == nil
    )
    check(
        "a rate of zero is paused, not absent",
        NowPlayingDirect.snapshot(from: mediaInfo(rate: 0))?.isPlaying == false
    )
    // A live stream reports no length. Dividing a progress bar by it gives
    // either a full bar or a crash, so it is treated as having none — which the
    // panel already knows how to draw.
    check(
        "a stream with no length reports none rather than zero",
        NowPlayingDirect.snapshot(from: mediaInfo(duration: 0))?.duration == nil
    )
    check(
        "a negative position is not believed",
        NowPlayingDirect.snapshot(from: mediaInfo(elapsed: -5))?.elapsed == 0
    )
    // The cover arrives as bytes from the system rather than a download, but it
    // is still decoded into an image on the main thread, so it is still bounded.
    check(
        "an absurd cover is refused",
        NowPlayingDirect.snapshot(
            from: mediaInfo(artwork: Data(count: NowPlayingDirect.maxArtworkBytes + 1))
        )?.artwork == nil
    )
    check(
        "an empty cover is refused",
        NowPlayingDirect.snapshot(from: mediaInfo(artwork: Data()))?.artwork == nil
    )
    check(
        "a track with no cover is still a track",
        NowPlayingDirect.snapshot(from: mediaInfo(artwork: nil))?.title == "Night Drive"
    )

    // The app now runs on macOS 12 through 26. Which generation it thinks it is
    // on decides how hard it works the compositor — never which features exist.
    check(
        "this Mac is placed in a generation",
        [.monterey, .modern, .latest].contains(SystemGeneration.current)
    )
    check(
        "every generation still animates",
        SystemGeneration.allCasesForChecks.allSatisfy { $0.motionScale > 0 }
    )
    // Older systems get MORE time per animation, not less: a spring that cannot
    // be drawn in time reads as stutter, the same spring slowed reads as
    // deliberate.
    check(
        "the oldest system is given the most time to animate",
        SystemGeneration.monterey.motionScale > SystemGeneration.latest.motionScale
    )
    check(
        "the newest system is not slowed down",
        SystemGeneration.latest.motionScale == 1.0
    )
    // Timing is now the only thing that varies by system — the panel's shadow
    // was the other, and it is drawn on no system at all. Every generation must
    // still be given a usable amount of it.
    check(
        "no generation is left without a workable animation speed",
        SystemGeneration.allCasesForChecks.allSatisfy { $0.motionScale >= 1.0 && $0.motionScale <= 2.0 }
    )

    // ── A reported position has to earn its place ───────────────────────────
    //
    // Between polls the bar runs on its own clock, which is what makes it move
    // smoothly instead of in one-second steps. A reported position measures the
    // same track a moment earlier, so the two are never exactly equal — and
    // adopting the report every time drags the readout back across a second
    // boundary and then forwards again. On screen: 1:41, 1:40, 1:41, over and
    // over, on a track playing perfectly normally.
    func at(_ elapsed: Double, _ seconds: Double, playing: Bool = true, length: Double = 300) -> MediaProgress {
        MediaProgress(
            elapsed: elapsed, duration: length, isPlaying: playing,
            at: Date(timeIntervalSince1970: seconds)
        )
    }
    // The bar is derived from the player's own pair — a position and the
    // instant it was true — and from nothing else. There is no second clock to
    // disagree with, which is what the counting 1, 2, 3, 1, 2, 3 actually was:
    // two extrapolations of one truth from two different starting instants,
    // arbitrated by a rule.
    check(
        "a playing track advances by the time since the player's reading",
        at(30, 10).current(now: Date(timeIntervalSince1970: 70)) == 90
    )
    check(
        "a paused track does not move, however long ago it was read",
        at(30, 10, playing: false).current(now: Date(timeIntervalSince1970: 9_000)) == 30
    )
    check(
        "the position at the instant of the reading is the reading",
        at(30, 10).current(now: Date(timeIntervalSince1970: 10)) == 30
    )
    // A player that stops reporting must not drive the bar past the end of the
    // track, which would show a full bar and a negative time remaining.
    check(
        "a stale reading cannot run past the end",
        at(280, 10, length: 300).current(now: Date(timeIntervalSince1970: 10_000)) == 300
    )
    check(
        "and cannot go negative if the clocks disagree",
        at(5, 100).current(now: Date(timeIntervalSince1970: 0)) == 0
    )

    // ── The reading is passed on, not interpreted ────────────────────────────
    //
    // kMRMediaRemoteNowPlayingInfoElapsedTime is where the track was at
    // kMRMediaRemoteNowPlayingInfoTimestamp, and macOS refreshes the pair only
    // when something HAPPENS — a pause, a seek, a track change — not while a
    // track simply plays. Taking the number at face value is wrong by however
    // long the track has been left alone: measured once at 217 seconds out.
    //
    // The correction used to be applied HERE, and then the monitor applied its
    // own on top from a different starting instant. That is what made the
    // readout count 1, 2, 3 and start again. So this layer now interprets
    // nothing: it hands on the player's figure and the instant it was true, and
    // the position is derived once, where it is drawn.
    let stamped = Date(timeIntervalSince1970: 1_000_000)
    func timed(rate: Double, elapsed: Double, duration: Double? = 240) -> [String: Any] {
        var info = mediaInfo(rate: rate, elapsed: elapsed, duration: duration)
        info["kMRMediaRemoteNowPlayingInfoTimestamp"] = stamped
        return info
    }
    check(
        "the player's own figure is passed on untouched",
        NowPlayingDirect.snapshot(
            from: timed(rate: 1, elapsed: 30), now: stamped.addingTimeInterval(60)
        )?.elapsed == 30
    )
    check(
        "and so is the instant it was true",
        NowPlayingDirect.snapshot(
            from: timed(rate: 1, elapsed: 30), now: stamped.addingTimeInterval(60)
        )?.elapsedAt == stamped
    )
    // Put the two together and the position comes out right — the same 90
    // seconds the old code computed here, now computed once, in one place.
    check(
        "the pair together gives the position", {
            guard let s = NowPlayingDirect.snapshot(
                from: timed(rate: 1, elapsed: 30), now: stamped.addingTimeInterval(60)
            ), let e = s.elapsed, let d = s.duration else { return false }
            let progress = MediaProgress(
                elapsed: e, duration: d, isPlaying: s.isPlaying, at: s.elapsedAt
            )
            return progress.current(now: stamped.addingTimeInterval(60)) == 90
        }()
    )
    // Older macOS may not send a timestamp at all. The moment of reading is
    // then the best available answer, and the pair still works.
    check(
        "a reading with no timestamp is stamped when it was read",
        NowPlayingDirect.snapshot(
            from: mediaInfo(rate: 1, elapsed: 30), now: stamped
        )?.elapsedAt == stamped
    )

    // The bundle id picks a CONTROL channel and nothing else. An app nobody
    // listed is not unsupported — it is shown, given artwork and read exactly
    // like any other, and simply takes the route that suits it.
    check(
        "Spotify is recognised so its own scripting can resume it",
        NowPlayingDirect.source(forBundleIdentifier: "com.spotify.client") == .spotify
    )
    check(
        "Music is recognised the same way",
        NowPlayingDirect.source(forBundleIdentifier: "com.apple.Music") == .music
    )
    check(
        "an app nobody listed still gets a channel",
        NowPlayingDirect.source(forBundleIdentifier: "com.anghami.desktop") == .other
    )
    check(
        "so does an app that names itself nothing at all",
        NowPlayingDirect.source(forBundleIdentifier: nil) == .other
    )

    // A command that did not take is discovered by MEASUREMENT — by asking
    // whether the player actually obeyed — not by recognising the app that is
    // playing. The system's media channel reports success for a browser and
    // does nothing (measured live: pause returned true, the playback rate
    // stayed at 1), so believing its answer is how a button comes to look
    // broken. Recognising browsers by bundle id instead would be wrong for
    // every browser not on the list and would need editing forever.
    check(
        "with browser control off, that is what the panel says",
        MediaMonitor.controlProblem(browserControlOn: false, accessibilityGranted: true)
            == .browserControlOff
    )
    check(
        "the switch being off is named before the permission",
        MediaMonitor.controlProblem(browserControlOn: false, accessibilityGranted: false)
            == .browserControlOff
    )
    check(
        "switched on but not permitted names the permission",
        MediaMonitor.controlProblem(browserControlOn: true, accessibilityGranted: false)
            == .accessibilityMissing
    )
    // Nothing the user could do about it is worse than saying nothing at all.
    check(
        "a failure with nothing to fix says nothing",
        MediaMonitor.controlProblem(browserControlOn: true, accessibilityGranted: true) == nil
    )

    // A cover is fetched off the polling queue so a track can appear without
    // waiting on an HTTP request — which means it can land after the user has
    // already skipped past the song it belongs to. The wrong album beside the
    // right title is a worse failure than the placeholder it would replace.
    check(
        "a cover is shown when its own track is still the one playing",
        MediaMonitor.acceptsArtwork(arrivedFor: "Night Drive", showing: "Night Drive")
    )
    check(
        "a cover that arrives after a skip is dropped",
        MediaMonitor.acceptsArtwork(arrivedFor: "Night Drive", showing: "Something Else") == false
    )
    check(
        "a cover arriving once the notch is empty is dropped",
        MediaMonitor.acceptsArtwork(arrivedFor: "Night Drive", showing: nil) == false
    )
    check(
        "a cover with no track to belong to is dropped",
        MediaMonitor.acceptsArtwork(arrivedFor: "", showing: "") == false
    )

    // Panel-only readouts sample only while anyone can see them.
    let visibility = PanelVisibility()
    var samples = 0
    let visible = VisibleSampler(interval: 60, visibility: visibility) { samples += 1 }
    visible.start()
    check("a shut panel samples nothing", samples == 0)
    visibility.setOpen(true)
    check("opening the panel samples at once", samples == 1)
    visibility.setOpen(true)
    check("staying open does not resample", samples == 1)
    visibility.setOpen(false)
    visibility.setOpen(true)
    // Deliberately NOT a fresh sample. The panel is opened by hovering a notch,
    // so it is opened by accident constantly, and some readings behind it are
    // expensive — the AirPods row spawns a subprocess, the token row rescans
    // transcripts. A value read a moment ago is still the value.
    check("reopening while the reading is still fresh does not repeat it", samples == 1)
    visible.stop()
    visibility.setOpen(false)
    visibility.setOpen(true)
    check("a stopped sampler ignores the panel", samples == 1)

    // But once the interval really has passed, a reopen must read again —
    // otherwise "don't repeat fresh work" quietly becomes "don't update".
    let brisk = PanelVisibility()
    var briskSamples = 0
    let briskSampler = VisibleSampler(interval: 0.05, visibility: brisk) { briskSamples += 1 }
    briskSampler.start()
    brisk.setOpen(true)
    let afterFirstOpen = briskSamples
    brisk.setOpen(false)
    Thread.sleep(forTimeInterval: 0.12)
    brisk.setOpen(true)
    check("reopening after the interval has passed does read again", briskSamples > afterFirstOpen)
    briskSampler.stop()

    // Watching a folder replaces re-listing it on a timer, so it has to
    // actually fire — a silent failure here would mean a finished download is
    // never announced again.
    let watchDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-watch-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)
    var changes = 0
    let watcher = DirectoryWatcher(url: watchDir, coalesce: 0.05) { changes += 1 }
    check("a folder that exists can be watched", watcher != nil)

    try? "x".write(to: watchDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    check("writing into the folder reports a change", changes >= 1)

    let afterFirst = changes
    try? "y".write(to: watchDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    check("the watch keeps working after the first change", changes > afterFirst)

    watcher?.stop()
    let afterStop = changes
    try? "z".write(to: watchDir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    check("a stopped watch reports nothing", changes == afterStop)

    check(
        "a folder that does not exist is not watched",
        DirectoryWatcher(url: watchDir.appendingPathComponent("nope"), onChange: {}) == nil
    )
    try? FileManager.default.removeItem(at: watchDir)

    // Throughput is a difference over time, so a reading taken after the panel
    // was shut (or the Mac asleep) is too old to diff against and is used as a
    // fresh baseline instead of being reported as the current speed.
    check("a fresh reading is usable", NetworkMonitor.isStaleBaseline(dt: 1.0, interval: 1.0) == false)
    check("a slightly late reading is usable", NetworkMonitor.isStaleBaseline(dt: 2.5, interval: 1.0) == false)
    check("a reading from minutes ago is not", NetworkMonitor.isStaleBaseline(dt: 600, interval: 1.0))

    // Data used. The figure is built from the kernel's per-interface counters,
    // which count from whenever each interface came up, so every rule below is
    // about turning a number that only grows into "how much of it is mine, and
    // when".
    check("loopback is not data used", NetworkUsageMath.counts("lo0") == false)
    check("a VPN tunnel is not counted twice", NetworkUsageMath.counts("utun3") == false)
    check("nor is an IPsec tunnel", NetworkUsageMath.counts("ipsec0") == false)
    check("AirDrop is not internet", NetworkUsageMath.counts("awdl0") == false)
    check("a bridge is the same bytes again", NetworkUsageMath.counts("bridge0") == false)
    check("so is a virtual machine's link", NetworkUsageMath.counts("vmenet0") == false)
    check("so is sharing this Mac's connection", NetworkUsageMath.counts("ap1") == false)
    check("the processors' own link is not the internet", NetworkUsageMath.counts("anpi0") == false)
    check("wi-fi is counted", NetworkUsageMath.counts("en0"))
    check("so is a second ethernet", NetworkUsageMath.counts("en7"))
    // Left in rather than left out: an interface nobody here anticipated is
    // counted, because a figure that is too high can be noticed and reported
    // and one that is too low looks exactly like a quiet day.
    check("an unfamiliar interface is counted rather than dropped", NetworkUsageMath.counts("wwan0"))

    check("a counter seen for the first time contributes nothing",
          NetworkUsageMath.delta(previous: nil, current: 8_000_000_000) == 0)
    check("a counter that grew contributes the difference",
          NetworkUsageMath.delta(previous: 100, current: 250) == 150)
    check("a counter that restarted contributes all it now holds",
          NetworkUsageMath.delta(previous: 900, current: 120) == 120)
    check("a counter that did not move contributes nothing",
          NetworkUsageMath.delta(previous: 500, current: 500) == 0)

    let usageCalendar = Calendar.current
    let usageNow = usageCalendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 14))!
    func reading(_ received: UInt64, _ sent: UInt64, at: Date, on name: String = "en0") -> [String: InterfaceBytes] {
        [name: InterfaceBytes(received: received, sent: sent, seenAt: at)]
    }

    // A fresh install meeting counters that already hold gigabytes must report
    // nothing, or its first second reads as the heaviest day of the month.
    let firstFold = NetworkUsageMath.folded(
        NetworkUsageLedger(),
        reading: reading(5_000_000_000, 1_000_000_000, at: usageNow),
        now: usageNow,
        calendar: usageCalendar
    )
    check("the first reading of all counts nothing",
          firstFold.days.first?.received == 0 && firstFold.days.first?.sent == 0)
    check("and the moment counting began is remembered", firstFold.countingSince == usageNow)

    let secondFold = NetworkUsageMath.folded(
        firstFold,
        reading: reading(5_000_300_000, 1_000_100_000, at: usageNow.addingTimeInterval(60)),
        now: usageNow.addingTimeInterval(60),
        calendar: usageCalendar
    )
    check("the second reading counts what arrived between them",
          secondFold.days.first?.received == 300_000 && secondFold.days.first?.sent == 100_000)
    check("and it lands on one day rather than two", secondFold.days.count == 1)

    // Wi-Fi switched off and on, or the Mac restarted: the counter starts again
    // and everything it holds now arrived since it did.
    let afterRestart = NetworkUsageMath.folded(
        secondFold,
        reading: reading(40_000, 10_000, at: usageNow.addingTimeInterval(120)),
        now: usageNow.addingTimeInterval(120),
        calendar: usageCalendar
    )
    check("a restarted counter adds what it holds, not a negative",
          afterRestart.days.first?.received == 340_000)

    // QUITTING AND REOPENING THE SAME DAY. The counters keep running while the
    // app does not, so what went through in between is found on the next
    // reading — and it all belongs to today, which is not in doubt. Counting it
    // is what makes the row "used today" rather than "used while the app
    // happened to be open".
    let sameDayGap = NetworkUsageMath.folded(
        afterRestart,
        reading: reading(40_000 + 6_000_000, 10_000 + 900_000, at: usageNow.addingTimeInterval(6 * 3600)),
        now: usageNow.addingTimeInterval(6 * 3600),
        calendar: usageCalendar
    )
    check(
        "hours with the app closed still count, on the same day",
        sameDayGap.days.first?.received == 6_340_000
    )
    check("and the day is still a whole day", sameDayGap.days.first?.isPartial == false)

    // Midnight with the app running: one reading before, one after, a minute
    // apart. An ordinary reading that lands on the new day.
    let lateNight = usageCalendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 23, minute: 59, second: 30))!
    let justAfter = lateNight.addingTimeInterval(60)
    let atMidnight = NetworkUsageMath.folded(
        afterRestart,
        reading: reading(60_000, 20_000, at: lateNight),
        now: lateNight,
        calendar: usageCalendar
    )
    let acrossMidnight = NetworkUsageMath.folded(
        atMidnight,
        reading: reading(90_000, 30_000, at: justAfter),
        now: justAfter,
        calendar: usageCalendar
    )
    check("a new day opens its own entry", acrossMidnight.days.count == 2)
    check("and yesterday keeps what it had", acrossMidnight.days.first?.received == 360_000)
    check("while today holds only today's", acrossMidnight.days.last?.received == 30_000)
    check("and neither day is called incomplete", acrossMidnight.days.allSatisfy { !$0.isPartial })

    let nextDay = justAfter
    let todayTotals = NetworkUsageMath.totals(
        acrossMidnight, period: .today, now: nextDay, calendar: usageCalendar
    )
    check("today's figure is today's alone", todayTotals.received == 30_000)
    let monthTotals = NetworkUsageMath.totals(
        acrossMidnight, period: .thisMonth, now: nextDay, calendar: usageCalendar
    )
    check("the month's figure is both days", monthTotals.received == 390_000)

    // Saying so when the figure covers less than its name claims.
    check("a month counted from part-way through says so", monthTotals.coversWholeSpan == false)
    check("and says from when", monthTotals.countedSince == usageNow)
    check("a day counted from before it began does not", todayTotals.coversWholeSpan)

    // AWAY FOR DAYS. Quit on Friday, reopen on Monday: the bytes in between are
    // real and are spread across three days in proportions nothing on this Mac
    // records. Putting them on Monday would invent the heaviest day of the
    // month out of a weekend, so they are refused and said to be missing.
    let mondayMorning = usageNow.addingTimeInterval(3 * 24 * 3600)
    let afterWeekend = NetworkUsageMath.folded(
        afterRestart,
        reading: reading(9_000_000_000, 2_000_000_000, at: mondayMorning),
        now: mondayMorning,
        calendar: usageCalendar
    )
    let mondayTotals = NetworkUsageMath.totals(
        afterWeekend, period: .today, now: mondayMorning, calendar: usageCalendar
    )
    check("a weekend away is not dumped on the day you come back", mondayTotals.received == 0)
    check("the day you come back says a stretch of it went uncounted", mondayTotals.missedTime)
    check(
        "and the days away are marked too, so the month admits the hole",
        NetworkUsageMath.totals(
            afterWeekend, period: .thisMonth, now: mondayMorning, calendar: usageCalendar
        ).missedTime
    )
    check(
        "what was counted before the gap is still counted",
        NetworkUsageMath.totals(
            afterWeekend, period: .thisMonth, now: mondayMorning, calendar: usageCalendar
        ).received == 340_000
    )
    // The next reading after coming back counts normally from the new footing,
    // rather than the refusal poisoning everything that follows.
    let backAtWork = NetworkUsageMath.folded(
        afterWeekend,
        reading: reading(9_000_500_000, 2_000_200_000, at: mondayMorning.addingTimeInterval(60)),
        now: mondayMorning.addingTimeInterval(60),
        calendar: usageCalendar
    )
    check(
        "and counting resumes properly from where it came back",
        NetworkUsageMath.totals(
            backAtWork, period: .today, now: mondayMorning.addingTimeInterval(60), calendar: usageCalendar
        ).received == 500_000
    )

    // An interface that disappears is remembered, so that its counters
    // restarting while it was away is still noticed when it comes back.
    let dockGone = NetworkUsageMath.folded(
        acrossMidnight,
        reading: [:],
        now: nextDay.addingTimeInterval(60),
        calendar: usageCalendar
    )
    check("an interface missing from a reading is remembered", dockGone.lastSeen["en0"] != nil)
    check("and a reading with nothing in it counts nothing",
          dockGone.days.last?.received == 30_000)

    // Reset: the day-by-day record is left alone, because today and this month
    // are read from the same days and have every right to them.
    let resetAt = nextDay.addingTimeInterval(120)
    let afterReset = NetworkUsageMath.afterReset(acrossMidnight, now: resetAt, calendar: usageCalendar)
    check("resetting keeps every day already counted", afterReset.days == acrossMidnight.days)
    check("and today still reads the same", NetworkUsageMath.totals(
        afterReset, period: .today, now: resetAt, calendar: usageCalendar
    ).received == 30_000)
    check("while the reset figure starts at nothing", NetworkUsageMath.totals(
        afterReset, period: .sinceReset, now: resetAt, calendar: usageCalendar
    ).received == 0)

    let afterResetAndUse = NetworkUsageMath.folded(
        afterReset,
        reading: reading(90_000 + 7_000, 30_000 + 2_000, at: resetAt.addingTimeInterval(60)),
        now: resetAt.addingTimeInterval(60),
        calendar: usageCalendar
    )
    check("the reset figure counts only what came after it", NetworkUsageMath.totals(
        afterResetAndUse, period: .sinceReset, now: resetAt.addingTimeInterval(60), calendar: usageCalendar
    ).received == 7_000)
    check("and the day's own figure still counts all of it", NetworkUsageMath.totals(
        afterResetAndUse, period: .today, now: resetAt.addingTimeInterval(60), calendar: usageCalendar
    ).received == 37_000)

    // The subtraction the reset performs is on unsigned numbers, and a day that
    // has been pruned out of the record would make it go below zero — which on
    // these types is not a negative, it is a number near eighteen quintillion.
    var pruned = afterResetAndUse
    pruned.days = pruned.days.map { DayUsage(day: $0.day, received: 0, sent: 0) }
    check("a figure that cannot be worked out is nothing, never a vast number",
          NetworkUsageMath.totals(pruned, period: .sinceReset, now: resetAt, calendar: usageCalendar).received == 0)

    // The record cannot grow without end: two months of days, and a ceiling on
    // how many interface names are remembered.
    var longRun = NetworkUsageLedger()
    for day in 0..<80 {
        let at = usageNow.addingTimeInterval(Double(day) * 24 * 60 * 60)
        longRun = NetworkUsageMath.folded(
            longRun,
            reading: reading(UInt64(day) * 1_000, UInt64(day) * 100, at: at),
            now: at,
            calendar: usageCalendar
        )
    }
    check("only two months of days are kept", longRun.days.count == NetworkUsageMath.historyLength)

    var manyInterfaces = NetworkUsageLedger()
    for index in 0..<50 {
        let at = usageNow.addingTimeInterval(Double(index))
        manyInterfaces = NetworkUsageMath.folded(
            manyInterfaces,
            reading: reading(1_000, 100, at: at, on: "en\(index)"),
            now: at,
            calendar: usageCalendar
        )
    }
    check("the remembered interfaces have a ceiling",
          manyInterfaces.lastSeen.count == NetworkUsageMath.interfaceLimit)

    // An interface gone long enough is forgotten, so a machine that names them
    // differently every time cannot fill the record with strangers.
    let staleAt = usageNow.addingTimeInterval(NetworkUsageMath.forgetInterfaceAfter + 60)
    let forgotten = NetworkUsageMath.folded(
        firstFold,
        reading: reading(1_000, 100, at: staleAt, on: "en9"),
        now: staleAt,
        calendar: usageCalendar
    )
    check("an interface gone for a month is forgotten", forgotten.lastSeen["en0"] == nil)

    // The record is kept in preferences, like the token count's cache, so the
    // promise that the app writes no files stays true.
    let usageDefaults = InMemoryDefaults()
    NetworkUsageStore.save(acrossMidnight, to: usageDefaults)
    check("the record survives a relaunch", NetworkUsageStore.load(from: usageDefaults) == acrossMidnight)
    NetworkUsageStore.clear(in: usageDefaults)
    check("and can be cleared", NetworkUsageStore.load(from: usageDefaults) == nil)

    // What the app actually reads from this Mac, checked against the rule.
    let liveReading = NetworkInterfaces.read()
    check("this Mac's own interfaces are read", liveReading.isEmpty == false)
    check("and none of them is one the rule excludes",
          liveReading.keys.allSatisfy { NetworkUsageMath.counts($0) })

    // The reading is parsed out of a run of variable-length kernel messages, so
    // it is cross-checked here against a completely different call that answers
    // the same question — `getifaddrs`, which the app deliberately does NOT use
    // because its counters are 32 bits wide and roll over every 4.29 GB.
    //
    // That narrowness is what makes it useful here: the low 32 bits of a
    // correct 64-bit reading are exactly what the old call reports. A
    // misaligned parse would not agree to within a few megabytes, it would
    // disagree by orders of magnitude.
    func getifaddrsBytes() -> [String: (received: UInt64, sent: UInt64)] {
        var out: [String: (received: UInt64, sent: UInt64)] = [:]
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return out }
        defer { freeifaddrs(addrs) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let sockaddr = interface.ifa_addr,
               sockaddr.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let name = String(cString: interface.ifa_name)
                if NetworkUsageMath.counts(name) {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    out[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
                }
            }
            cursor = interface.ifa_next
        }
        return out
    }

    let independent = getifaddrsBytes()
    check(
        "the same interfaces are found by a completely different call",
        Set(liveReading.keys) == Set(independent.keys)
    )
    // Generous, because the two readings are taken microseconds apart on a live
    // machine and a busy link moves between them. Tight enough that a wrong
    // offset — which yields nonsense in the exabytes — cannot pass.
    let tolerance: UInt64 = 50_000_000
    let wrap = UInt64(UInt32.max) + 1
    var agree = true
    for (name, bytes) in liveReading {
        guard let other = independent[name] else { agree = false; continue }
        let lowReceived = bytes.received % wrap
        let lowSent = bytes.sent % wrap
        let dr = lowReceived > other.received ? lowReceived - other.received : other.received - lowReceived
        let ds = lowSent > other.sent ? lowSent - other.sent : other.sent - lowSent
        if dr > tolerance || ds > tolerance { agree = false }
    }
    check("and it agrees with them, to the bit where the old call runs out", agree)

    // The property the whole figure rests on: folding a run of readings adds up
    // to exactly the difference between the first and the last. Nothing is
    // counted twice and nothing is dropped in between, however many readings
    // there are — and it is why macOS rounding each reading down to a kilobyte
    // cannot accumulate: the rounding cancels between one reading and the next,
    // leaving at most the last one's remainder outstanding.
    var telescoping = NetworkUsageLedger()
    let base: UInt64 = 4_000_000_000
    let steps: [UInt64] = [0, 1_024, 50_000, 3_000_000, 3_000_001, 900_000_000]
    for (index, step) in steps.enumerated() {
        let at = usageNow.addingTimeInterval(Double(index) * 60)
        telescoping = NetworkUsageMath.folded(
            telescoping,
            reading: reading(base + step, base + step / 2, at: at),
            now: at,
            calendar: usageCalendar
        )
    }
    check(
        "a run of readings adds up to exactly the distance between the ends",
        telescoping.days.first?.received == steps.last! - steps.first!
    )
    check(
        "and the same holds for what was sent",
        telescoping.days.first?.sent == steps.last! / 2 - steps.first! / 2
    )

    // Counters only ever climb. A reading that went backwards between two looks
    // a moment apart would mean the parse is picking up a different field each
    // time, which is the failure this whole feature would be built on.
    let secondReading = NetworkInterfaces.read()
    check(
        "reading twice never goes backwards",
        liveReading.allSatisfy { name, bytes in
            guard let later = secondReading[name] else { return true }
            return later.received >= bytes.received && later.sent >= bytes.sent
        }
    )

    // WHICH PROGRAMS THE TRAFFIC WENT THROUGH. A different reading from every
    // other one in this feature: the interface counters know how much went past
    // and nothing about who sent it, and this one names programs. Its rules
    // mirror the totals' deliberately, except where a process is genuinely not
    // an interface — which is the interesting case and is checked hardest.
    check("a process key becomes its program",
          NetworkAppUsageMath.programName(fromKey: "Safari.402") == "Safari")
    check("a program whose name has dots keeps them",
          NetworkAppUsageMath.programName(fromKey: "com.apple.WebKit.884") == "com.apple.WebKit")
    check("a key with no pid is not a process line",
          NetworkAppUsageMath.programName(fromKey: "bytes_in") == nil)
    check("nor is one whose tail is not a number",
          NetworkAppUsageMath.programName(fromKey: "Safari.abc") == nil)
    check("nor is a bare pid with no program",
          NetworkAppUsageMath.programName(fromKey: ".402") == nil)
    // A browser does its networking in child processes. Leaving the suffix on
    // would list one program twice, with its data split between the two rows
    // and neither of them true.
    check("a helper counts as the program it belongs to",
          NetworkAppUsageMath.programName(fromKey: "Claude Helper.1507") == "Claude")
    check("and so does a renderer",
          NetworkAppUsageMath.programName(fromKey: "Chrome Helper (Renderer).91") == "Chrome")
    check("a name that is only a suffix is left alone",
          NetworkAppUsageMath.programName(fromKey: " Helper.5") == " Helper")
    // Nothing is invented to complete a name macOS truncated.
    check("a name macOS cut short is shown as it came",
          NetworkAppUsageMath.programName(fromKey: "AMPDeviceDiscov.649") == "AMPDeviceDiscov")
    // Except a helper whose own suffix was cut off, which is the browser's
    // traffic wearing a name that belongs to nothing.
    check("a helper cut short still counts as its program",
          NetworkAppUsageMath.programName(fromKey: "Google Chrome H.77") == "Google Chrome")
    check("and so does one cut at a different letter",
          NetworkAppUsageMath.programName(fromKey: "Adobe Reader He.9") == "Adobe Reader")
    // A name LONGER than the cut was never cut, so it keeps what it has.
    check("a name past the cut is not treated as cut",
          NetworkAppUsageMath.programName(fromKey: "Some Long App He.9") == "Some Long App He")
    // Only at the exact length macOS cuts to, so a real name of that length
    // keeps every letter.
    check("a full name of the same length is left alone",
          NetworkAppUsageMath.programName(fromKey: "Microsoft Excel.5") == "Microsoft Excel")
    check("and so is another",
          NetworkAppUsageMath.programName(fromKey: "AMPLibraryAgent.5") == "AMPLibraryAgent")
    check("a short name ending in something else is untouched",
          NetworkAppUsageMath.programName(fromKey: "Mail.4") == "Mail")

    // The delta rule, which is where this differs from the interface one ON
    // PURPOSE. An interface's counter starts when the Mac boots, so its first
    // value is history. A process's counter starts when the process does, so
    // the first value of a process met since the last look is not.
    check("nothing at all is counted from the very first sample",
          NetworkAppUsageMath.delta(previous: nil, current: 9_000_000, hasStarted: false) == 0)
    check("a process met since the last look contributes all it holds",
          NetworkAppUsageMath.delta(previous: nil, current: 9_000_000, hasStarted: true) == 9_000_000)
    check("a process that grew contributes the difference",
          NetworkAppUsageMath.delta(previous: 400, current: 900, hasStarted: true) == 500)
    check("a reused process id contributes what it now holds",
          NetworkAppUsageMath.delta(previous: 900, current: 30, hasStarted: true) == 30)

    func appReading(_ pairs: [(String, UInt64, UInt64)], at: Date) -> [String: ProcessBytes] {
        var result: [String: ProcessBytes] = [:]
        for (key, received, sent) in pairs {
            result[key] = ProcessBytes(received: received, sent: sent, seenAt: at)
        }
        return result
    }

    let appsFirst = NetworkAppUsageMath.folded(
        AppUsageLedger(),
        reading: appReading([("Safari.1", 5_000_000, 900_000), ("Mail.2", 100, 100)], at: usageNow),
        now: usageNow,
        calendar: usageCalendar
    )
    check("the first sample of all records nothing",
          appsFirst.days.first?.apps.isEmpty ?? true)
    check("but it is remembered as the baseline", appsFirst.started)

    let appsSecond = NetworkAppUsageMath.folded(
        appsFirst,
        reading: appReading(
            [("Safari.1", 5_300_000, 950_000), ("Mail.2", 100, 100)],
            at: usageNow.addingTimeInterval(60)),
        now: usageNow.addingTimeInterval(60),
        calendar: usageCalendar
    )
    check("the second sample counts what arrived between them",
          appsSecond.days.first?.apps["Safari"] == AppBytes(received: 300_000, sent: 50_000))
    check("a process that sent nothing is not written down at all",
          appsSecond.days.first?.apps["Mail"] == nil)

    // Two processes of one program add up as one program.
    let appsMerged = NetworkAppUsageMath.folded(
        appsSecond,
        reading: appReading(
            [("Safari.1", 5_400_000, 950_000), ("Safari Helper.9", 70_000, 0)],
            at: usageNow.addingTimeInterval(120)),
        now: usageNow.addingTimeInterval(120),
        calendar: usageCalendar
    )
    check("a program and its helper are one row",
          appsMerged.days.first?.apps["Safari"]?.received == 470_000)

    // The same refusal the totals make: the app was away across a change of
    // day, so what went through cannot be put against any one of them.
    let nextWeek = usageNow.addingTimeInterval(3 * 24 * 3600)
    let appsAfterGap = NetworkAppUsageMath.folded(
        appsMerged,
        reading: appReading([("Safari.1", 9_000_000_000, 950_000)], at: nextWeek),
        now: nextWeek,
        calendar: usageCalendar
    )
    check("a weekend the app was closed for is refused, not invented",
          appsAfterGap.days.last?.apps["Safari"] == nil)

    // One day's record cannot grow without end.
    var crowded: [String: AppBytes] = [:]
    for index in 0..<40 {
        crowded["app\(index)"] = AppBytes(received: UInt64(index) * 1000, sent: 0)
    }
    let kept = NetworkAppUsageMath.trimmed(crowded)
    check("a day keeps only the biggest few programs",
          kept.count == NetworkAppUsageMath.appsPerDay)
    check("and keeps the biggest ones", kept["app39"] != nil && kept["app0"] == nil)

    // Nor can the between-readings record.
    var manyProcesses: [String: ProcessBytes] = [:]
    for index in 0..<(NetworkAppUsageMath.processLimit + 60) {
        manyProcesses["p\(index).\(index)"] =
            ProcessBytes(received: 10, sent: 10, seenAt: usageNow)
    }
    let crowdedLedger = NetworkAppUsageMath.folded(
        AppUsageLedger(), reading: manyProcesses, now: usageNow, calendar: usageCalendar)
    check("no more processes are remembered than the ceiling allows",
          crowdedLedger.lastSeen.count == NetworkAppUsageMath.processLimit)

    // A process id is handed back and given to something else, so one is not
    // remembered for long.
    // Measured from when those processes were last SEEN (usageNow + 120), not
    // from usageNow — the first draft of this check got that wrong and the
    // check caught it.
    let staleProcess = NetworkAppUsageMath.folded(
        appsMerged,
        reading: [:],
        now: usageNow.addingTimeInterval(120 + NetworkAppUsageMath.forgetProcessAfter + 60),
        calendar: usageCalendar
    )
    check("a process gone long enough is forgotten rather than kept forever",
          staleProcess.lastSeen.isEmpty)

    // What the panel actually asks for.
    let ranking = AppUsageLedger(days: [
        AppDayUsage(day: usageCalendar.startOfDay(for: usageNow), apps: [
            "Safari": AppBytes(received: 900, sent: 100),
            "Mail": AppBytes(received: 8_000, sent: 400),
            "Music": AppBytes(received: 50, sent: 0),
            "Idle": AppBytes(received: 0, sent: 0),
        ]),
    ])
    let topUsers = NetworkAppUsageMath.topApps(
        ranking, from: usageNow, limit: 2, calendar: usageCalendar)
    check("the panel is given the biggest first", topUsers.first?.name == "Mail")
    check("and only as many as it asked for", topUsers.count == 2)
    check("a program that used nothing is not offered at all",
          NetworkAppUsageMath.topApps(ranking, from: usageNow, limit: 10, calendar: usageCalendar)
              .contains { $0.name == "Idle" } == false)
    check("what a program used is what it used",
          topUsers.first?.received == 8_000 && topUsers.first?.sent == 400)

    // Two spellings of one program. macOS reports `claude` and `Claude`
    // separately and in a strict sense they are two things — a command and an
    // application — but two rows wearing the same word reads as the app having
    // counted something twice, which costs trust even when both figures are
    // right. Folded at the point of display; the record underneath keeps them
    // apart.
    let twoClaudes: [String: AppBytes] = [
        "claude": AppBytes(received: 100, sent: 900),
        "Claude": AppBytes(received: 10, sent: 40),
        "Mail": AppBytes(received: 7, sent: 3),
    ]
    let folded = NetworkAppUsageMath.merged(twoClaudes)
    check("two spellings of one program become one row", folded.count == 2)
    check("and their figures are added rather than one replacing the other",
          folded["Claude"] == AppBytes(received: 110, sent: 940))
    check("a program with only one spelling is untouched",
          folded["Mail"] == AppBytes(received: 7, sent: 3))

    // A record written before a tidying rule existed still reads correctly,
    // without anything having to migrate it: the same browser recorded under a
    // cut-short helper name and under its real one is one row, not two.
    let mixedRecord: [String: AppBytes] = [
        "Google Chrome H": AppBytes(received: 500, sent: 20),
        "Google Chrome": AppBytes(received: 100, sent: 5),
    ]
    let healed = NetworkAppUsageMath.merged(mixedRecord)
    check("an old name and a new one for the same program are one row",
          healed.count == 1 && healed["Google Chrome"] == AppBytes(received: 600, sent: 25))

    // The surviving spelling is the one that looks like an application, even
    // when it is the smaller of the two — which is the case that matters, since
    // the command-line tool is usually the heavier one.
    check("the capitalised spelling is the one shown", folded["claude"] == nil)
    check("an application name beats a command name",
          NetworkAppUsageMath.preferredName("claude", "Claude", totals: twoClaudes) == "Claude")
    // Between two of the same kind, the bigger wins.
    let sameKind: [String: AppBytes] = [
        "node": AppBytes(received: 10, sent: 0),
        "NODE": AppBytes(received: 99, sent: 0),
    ]
    check("between two application-looking names the bigger wins",
          NetworkAppUsageMath.preferredName("NODE", "Node", totals: ["NODE": AppBytes(received: 99, sent: 0),
                                                                    "Node": AppBytes(received: 1, sent: 0)]) == "NODE")
    check("and two lower-case names go the same way",
          NetworkAppUsageMath.preferredName("node", "nODE", totals: ["node": AppBytes(received: 1, sent: 0),
                                                                     "nODE": AppBytes(received: 9, sent: 0)]) == "nODE")
    // An exact tie cannot be allowed to flicker between two draws.
    check("an exact tie is broken the same way every time",
          NetworkAppUsageMath.preferredName("bbb", "aaa", totals: sameKind) == "aaa")

    // A reset part-way through a day, mirroring the totals: what the day
    // already held is not part of "since you reset it".
    let resetRanking = NetworkAppUsageMath.afterReset(
        ranking, now: usageNow, calendar: usageCalendar)
    check("a reset remembers what the day already held",
          resetRanking.reset?.dayApps["Mail"] == AppBytes(received: 8_000, sent: 400))
    let afterResetTop = NetworkAppUsageMath.topApps(
        resetRanking, from: usageNow, limit: 2, calendar: usageCalendar)
    check("and what came before it is not counted again",
          afterResetTop.contains { $0.name == "Mail" } == false)

    // The parse. Real output, so the shape is pinned rather than assumed.
    let nettopOutput = """
    ,bytes_in,bytes_out,
    apsd.378,698316,709766,
    Claude Helper.1507,199549,2079015,
    claude.4555,89869,13754712,
    rubbish,1,
    broken.12,notanumber,5,
    """
    let parsedProcesses = AppTrafficReader.parse(nettopOutput, at: usageNow)
    check("the header line is not a process", parsedProcesses.count == 3)
    check("a real line is read exactly",
          parsedProcesses["claude.4555"]
              == ProcessBytes(received: 89_869, sent: 13_754_712, seenAt: usageNow))
    check("a line with missing fields is skipped", parsedProcesses["rubbish"] == nil)
    check("so is one whose counters are not numbers", parsedProcesses["broken.12"] == nil)

    // The record survives a relaunch, and clearing it is what switching the
    // breakdown off does.
    NetworkAppUsageStore.save(appsMerged, to: usageDefaults)
    check("the breakdown survives a relaunch",
          NetworkAppUsageStore.load(from: usageDefaults) == appsMerged)
    NetworkAppUsageStore.clear(from: usageDefaults)
    check("and switching it off leaves nothing behind",
          NetworkAppUsageStore.load(from: usageDefaults) == nil)

    // The list opens and shuts, so it can afford more than the two it showed
    // when it was a flat run of rows — and still fewer than a day keeps, so it
    // never runs out before the record does.
    check("the list is offered three programs", NetworkMonitor.topAppCount == 3)
    check("and a day keeps more than the list can show",
          NetworkAppUsageMath.appsPerDay > NetworkMonitor.topAppCount)

    // The bar under each program. Measured against the biggest in the list
    // rather than against the grand total, floored so a small one is still
    // visibly a bar, and never past the end of the row.
    check("the biggest program fills the row",
          NetworkAppUsageMath.barWidth(total: 100, biggest: 100, full: 260, floor: 4) == 260)
    check("half of the biggest is half the row",
          NetworkAppUsageMath.barWidth(total: 50, biggest: 100, full: 260, floor: 4) == 130)
    check("a tiny one is still drawn as a bar",
          NetworkAppUsageMath.barWidth(total: 1, biggest: 10_000_000, full: 260, floor: 4) == 4)
    check("a program that used nothing is drawn as nothing",
          NetworkAppUsageMath.barWidth(total: 0, biggest: 100, full: 260, floor: 4) == 0)
    check("nothing can run past the end of the row",
          NetworkAppUsageMath.barWidth(total: 500, biggest: 100, full: 260, floor: 4) == 260)
    check("and the floor never does either",
          NetworkAppUsageMath.barWidth(total: 1, biggest: 10_000, full: 2, floor: 4) == 2)
    check("no biggest yet means no bar",
          NetworkAppUsageMath.barWidth(total: 10, biggest: 0, full: 260, floor: 4) == 0)

    check("a bar that is all download is all one colour",
          NetworkAppUsageMath.downShare(received: 90, total: 90) == 1)
    check("a bar that is all upload is all the other",
          NetworkAppUsageMath.downShare(received: 0, total: 90) == 0)
    check("and one that is half each is split down the middle",
          NetworkAppUsageMath.downShare(received: 45, total: 90) == 0.5)
    check("an empty program cannot divide by zero",
          NetworkAppUsageMath.downShare(received: 0, total: 0) == 0)

    // THE HOOK ON DISK versus the hook this build ships. The hook is copied
    // into the home folder so it can be read before it runs, and the price of
    // that is that it does not follow the app — which has already cost one
    // change that shipped and never arrived.
    let hookV9 = "#!/bin/sh\n# comment mentioning HOOK_VERSION= in prose\nHOOK_VERSION=9\necho hi\n"
    let hookV7 = "#!/bin/sh\nHOOK_VERSION=7\necho hi\n"
    let hookNoStamp = "#!/bin/sh\necho hi\n"

    check("the stamp is read from the line that sets it",
          HookInstallation.version(in: hookV9) == 9)
    check("and prose that merely mentions it is not the stamp",
          HookInstallation.version(in: "# grep HOOK_VERSION= the-file\nHOOK_VERSION=3\n") == 3)
    check("a hook with no stamp has no version",
          HookInstallation.version(in: hookNoStamp) == nil)
    check("a stamp that is not a number is not a version",
          HookInstallation.version(in: "HOOK_VERSION=nine\n") == nil)

    check("an older hook on disk is out of date",
          HookInstallation.state(installed: hookV7, available: hookV9)
              == .outOfDate(installed: 7, available: 9))
    check("the same version is current",
          HookInstallation.state(installed: hookV9, available: hookV9) == .current)
    // An older app with a newer hook is somebody mid-upgrade, not somebody to
    // tell that their hook is behind.
    check("a newer hook on disk is not called out of date",
          HookInstallation.state(installed: hookV9, available: hookV7) == .current)
    check("no hook installed is not a problem",
          HookInstallation.state(installed: nil, available: hookV9) == .notInstalled)
    // Running unbundled: nothing to compare against, so nothing is claimed.
    check("with nothing to compare against, nothing is said",
          HookInstallation.state(installed: hookV9, available: nil) == .unknown)
    check("an unreadable stamp says nothing rather than guessing",
          HookInstallation.state(installed: hookNoStamp, available: hookV9) == .unknown)

    // Only one of these states interrupts anybody.
    check("only being out of date is worth a notice",
          HookState.outOfDate(installed: 1, available: 2).needsAttention
              && !HookState.current.needsAttention
              && !HookState.notInstalled.needsAttention
              && !HookState.unknown.needsAttention)

    // The comparison is the VERSION and deliberately not the bytes. The docs
    // invite people to open the hook and read it, and a byte comparison would
    // nag everybody who changed a comment in their own copy, for ever.
    let edited = "#!/bin/sh\nHOOK_VERSION=9\necho hi\n# my own note\n"
    check("somebody who edited their own hook is never nagged",
          HookInstallation.state(installed: edited, available: hookV9) == .current)

    // Activities feed: other processes write it, so every field is bounded
    // before it reaches the UI.
    let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
    let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))

    let feed = tempFile("""
    [
      {"id": "a", "title": "First", "progress": 2.5},
      {"id": "a", "title": "Duplicate of first"},
      {"id": "b", "title": "Second", "progress": -1, "endsAt": "\(future)"},
      {"id": "", "title": "No id"},
      {"id": "c", "title": ""},
      {"id": "d", "title": "Expired", "endsAt": "\(past)"}
    ]
    """)
    let parsed = ActivitiesReader.read(from: feed)
    check("feed keeps first of duplicate ids", parsed.map(\.id) == ["a", "b"])
    check("feed keeps titles", parsed.first?.title == "First")
    check("feed clamps progress high", parsed.first?.progress == 1)
    check("feed clamps progress low", parsed.last?.progress == 0)
    check("feed drops expired", !parsed.contains { $0.id == "d" })
    try? FileManager.default.removeItem(at: feed)

    let overflowing = (0..<20).map { "{\"id\": \"x\($0)\", \"title\": \"Item \($0)\"}" }
    let bigFeed = tempFile("[\(overflowing.joined(separator: ","))]")
    check("feed caps activity count", ActivitiesReader.read(from: bigFeed).count == ActivitiesReader.maxActivities)
    try? FileManager.default.removeItem(at: bigFeed)

    let hugeFeed = tempFile("[{\"id\": \"a\", \"title\": \"\(String(repeating: "x", count: ActivitiesReader.maxFeedBytes))\"}]")
    check("feed refuses oversized file", ActivitiesReader.read(from: hugeFeed).isEmpty)
    try? FileManager.default.removeItem(at: hugeFeed)

    let badFeed = tempFile("this is not json")
    check("feed tolerates invalid JSON", ActivitiesReader.read(from: badFeed).isEmpty)
    try? FileManager.default.removeItem(at: badFeed)

    let fractional = tempFile("[{\"id\": \"f\", \"title\": \"Fractional\", \"endsAt\": \"2099-01-01T12:00:00.500Z\"}]")
    check("feed parses fractional endsAt", ActivitiesReader.read(from: fractional).first?.endsAt != nil)
    try? FileManager.default.removeItem(at: fractional)

    // A logo path comes from the same untrusted feed as everything else, so it
    // is only honoured when it names a readable image that really exists.
    let logoDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-logo-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: logoDir, withIntermediateDirectories: true)
    let realLogo = logoDir.appendingPathComponent("brand.png")
    // A one-pixel PNG is enough: the reader checks the file, not the pixels.
    let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    try? onePixelPNG.write(to: realLogo)
    let notAnImage = logoDir.appendingPathComponent("notes.txt")
    try? "hello".write(to: notAnImage, atomically: true, encoding: .utf8)

    func imagePath(forFeed value: String) -> String? {
        let file = tempFile("[{\"id\":\"L\",\"title\":\"Logo\",\"image\":\"\(value)\"}]")
        defer { try? FileManager.default.removeItem(at: file) }
        return ActivitiesReader.read(from: file).first?.imagePath
    }

    check("a real image is accepted", imagePath(forFeed: realLogo.path) == realLogo.path)
    check("a missing file is refused", imagePath(forFeed: logoDir.appendingPathComponent("gone.png").path) == nil)
    check("a non-image file is refused", imagePath(forFeed: notAnImage.path) == nil)
    check("a folder is refused", imagePath(forFeed: logoDir.path) == nil)
    check("an empty path is refused", imagePath(forFeed: "") == nil)
    check(
        "a path that climbs out is resolved before it is judged",
        imagePath(forFeed: logoDir.appendingPathComponent("../../etc/passwd").path) == nil
    )

    // Size is part of the same judgement: the logo is decoded on the main
    // thread, so an oversized one is refused before it can ever reach it.
    let hugeLogo = logoDir.appendingPathComponent("huge.png")
    var oversized = onePixelPNG
    oversized.append(Data(count: ActivitiesReader.maxImageBytes))
    try? oversized.write(to: hugeLogo)
    check("an oversized image is refused", imagePath(forFeed: hugeLogo.path) == nil)

    let emptyLogo = logoDir.appendingPathComponent("empty.png")
    try? Data().write(to: emptyLogo)
    check("an empty image is refused", imagePath(forFeed: emptyLogo.path) == nil)

    // The app an activity names is a capability, not a hint: clicking the row
    // hands it to NSWorkspace, which STARTS a bundle that is not already
    // running. So it is bounded like every other field from the feed, and then
    // bounded again on where it lives — only the folders macOS keeps
    // applications in. A feed anyone can write must not be able to dress a
    // dropped bundle up as the window you were working in.
    //
    // `appsRoot` stands in for /Applications here so the rule itself is what is
    // being measured, rather than whatever happens to be installed.
    let appsRoot = logoDir.appendingPathComponent("Applications")
    try? FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)

    func appPath(forFeed value: String, roots: [String] = [appsRoot.path]) -> String? {
        let file = tempFile("[{\"id\":\"A\",\"title\":\"Jump\",\"app\":\"\(value)\"}]")
        defer { try? FileManager.default.removeItem(at: file) }
        return ActivitiesReader.read(from: file, appRoots: roots).first?.appPath
    }

    let installedApp = appsRoot.appendingPathComponent("Pretend.app")
    try? FileManager.default.createDirectory(at: installedApp, withIntermediateDirectories: true)
    check("an installed app bundle is accepted", appPath(forFeed: installedApp.path) == installedApp.path)
    check("a loose executable is refused", appPath(forFeed: "/bin/sh") == nil)
    check("a plain file named .app is refused", appPath(forFeed: notAnImage.path) == nil)
    check("a missing bundle is refused", appPath(forFeed: appsRoot.appendingPathComponent("Gone.app").path) == nil)
    check("an empty app path is refused", appPath(forFeed: "") == nil)
    check(
        "an app path that climbs out is resolved before it is judged",
        appPath(forFeed: appsRoot.appendingPathComponent("../../../bin/sh").path) == nil
    )

    // A bundle dropped somewhere out of the way is the whole reason the rule
    // exists: it can be a perfectly real .app and must still be refused.
    let strayApp = logoDir.appendingPathComponent("Update.app")
    try? FileManager.default.createDirectory(at: strayApp, withIntermediateDirectories: true)
    check("an app outside the standard folders is refused", appPath(forFeed: strayApp.path) == nil)

    // A symlink standing in an allowed folder while pointing outside it is the
    // way around a check that only reads the path as text.
    let disguised = appsRoot.appendingPathComponent("Innocent.app")
    try? FileManager.default.createSymbolicLink(at: disguised, withDestinationURL: strayApp)
    check("a link into an allowed folder is followed before it is judged", appPath(forFeed: disguised.path) == nil)

    // And the folder name is matched on its parts, not as a prefix of the text.
    let lookalike = logoDir.appendingPathComponent("Applications-mine")
    try? FileManager.default.createDirectory(at: lookalike, withIntermediateDirectories: true)
    let lookalikeApp = lookalike.appendingPathComponent("Evil.app")
    try? FileManager.default.createDirectory(at: lookalikeApp, withIntermediateDirectories: true)
    check("a folder that merely starts the same is refused", appPath(forFeed: lookalikeApp.path) == nil)

    // The allowed folders are the ones macOS actually keeps applications in.
    check(
        "the standard folders are where macOS keeps applications",
        ActivitiesReader.standardAppRoots.contains("/Applications")
            && ActivitiesReader.standardAppRoots.contains("/System/Applications")
    )

    // The rule is only worth anything if it still accepts the apps really
    // installed on this Mac, so it is measured against them rather than against
    // a fixture that agrees with it by construction.
    //
    // This is the check that catches the Safari case: /Applications/Safari.app
    // is a SYMLINK into Apple's signed cryptex volume, so resolving the path
    // before judging it — which is what stops a link pointing out of an allowed
    // folder — moves Safari outside /Applications. A rule written only against
    // temporary folders passes happily while refusing the browser.
    var refusedRealApps: [String] = []
    for root in ["/Applications", "/System/Applications"] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        for entry in entries where entry.hasSuffix(".app") {
            let path = root + "/" + entry
            if appPath(forFeed: path, roots: ActivitiesReader.standardAppRoots) == nil {
                refusedRealApps.append(path)
            }
        }
    }
    if !refusedRealApps.isEmpty {
        print("       refused: \(refusedRealApps.joined(separator: ", "))")
    }
    check("every app actually installed on this Mac is accepted", refusedRealApps.isEmpty)
    check(
        "an activity that names no app simply has none",
        ActivitiesReader.read(from: tempFile("[{\"id\":\"N\",\"title\":\"None\"}]"))
            .first?.appPath == nil
    )

    // A notice's few seconds must start when THAT notice arrives. Posters reuse
    // an id on purpose — it is how the feed merges — so judging a new alert by
    // the id alone measured it against the PREVIOUS one's clock, found it long
    // past, and dropped it before it ever drew. Every repeat alert vanished in
    // silence, which is the worst way for an alert to fail.
    func notice(_ id: String, endsAt: String) -> LiveActivity {
        LiveActivity(
            id: id, icon: "checkmark", title: "Claude finished", subtitle: nil,
            progress: nil, endsAt: ISO8601DateFormatter().date(from: endsAt),
            dismissAfter: 3
        )
    }
    let firstAlert = notice("claude-code", endsAt: "2099-01-01T12:00:03Z")
    let secondAlert = notice("claude-code", endsAt: "2099-01-01T12:05:41Z")

    check(
        "a notice never seen before starts its clock",
        ActivitiesMonitor.startsFresh(firstAlert, previously: nil)
    )
    check(
        "re-reading the same notice does not restart its clock",
        ActivitiesMonitor.startsFresh(firstAlert, previously: firstAlert) == false
    )
    check(
        "a later alert reusing the same id starts its own clock",
        ActivitiesMonitor.startsFresh(secondAlert, previously: firstAlert)
    )
    check(
        "a countdown keeps no notice clock at all",
        ActivitiesMonitor.startsFresh(
            LiveActivity(
                id: "c", icon: "bicycle", title: "Delivery", subtitle: nil, progress: nil,
                endsAt: Date().addingTimeInterval(600), dismissAfter: nil
            ),
            previously: nil
        ) == false
    )

    // The colour the island wears for something posted to the feed. The rule
    // is the difference between a fact and a request, and it is asked of every
    // poster alike — no tool is named anywhere in it.
    let finishedAlert = LiveActivity(
        id: "claude-code", icon: "checkmark", title: "Claude finished", subtitle: "notch",
        progress: nil, endsAt: Date().addingTimeInterval(3), dismissAfter: 3
    )
    let waitingAlert = LiveActivity(
        id: "claude-code", icon: "questionmark", title: "Claude needs you", subtitle: "notch",
        progress: nil, endsAt: Date().addingTimeInterval(45), dismissAfter: nil
    )
    let workingAlert = LiveActivity(
        id: "build", icon: "hammer", title: "Building", subtitle: nil,
        progress: 0.4, endsAt: nil, dismissAfter: nil
    )
    check(
        "something that finished lights the island",
        ActivitiesFeature.tint(for: finishedAlert) != nil
    )
    // Green, and the same green the battery wears when it is charging or full:
    // both are saying "this is fine, there is nothing for you to do", and two
    // greens a shade apart would read as two different meanings.
    check(
        "and it lights it green, the colour that means nothing is wanted of you",
        ActivitiesFeature.tint(for: finishedAlert) == Color(red: 0.30, green: 0.85, blue: 0.39)
    )
    // The badge beside the words and the ring around the notch are one signal,
    // so they are asked of one rule. If the mark ever picks its own colour, a
    // green ring with an orange badge inside it is what it would look like.
    check(
        "the badge beside the words wears the same colour as the ring",
        ActivitiesFeature.markTint(for: finishedAlert, accent: .orange)
            == ActivitiesFeature.tint(for: finishedAlert)
    )
    check(
        "and the one waiting on you does too",
        ActivitiesFeature.markTint(for: waitingAlert, accent: .orange)
            == ActivitiesFeature.tint(for: waitingAlert)
    )
    // Work in progress lights no edge, so the badge falls back to the accent
    // rather than to nothing.
    check(
        "work in progress keeps the accent for its badge",
        ActivitiesFeature.markTint(for: workingAlert, accent: .orange) == .orange
    )

    // How long something has waited, said plainly. A request used to show the
    // time LEFT before it gave up — a countdown on a question, which measures
    // when the app stops asking rather than how long the answer has been owed.
    check("nothing is said for the first minute", Formatters2.waited(45) == nil)
    check("then it counts up", Formatters2.waited(60) == "1 min")
    check("and keeps counting", Formatters2.waited(11 * 60 + 30) == "11 min")
    check("past an hour it says hours", Formatters2.waited(3 * 3600 + 240) == "3h 4m")

    // A wait presses harder as it goes on: the line breathes faster and stops
    // dimming as far. Gentle at both ends — this is the whole escalation, and
    // it never becomes a flash.
    check("a request just arrived is not urgent yet", ActivitiesFeature.urgency(waitedSeconds: 5) == 0)
    check("nor at half a minute", ActivitiesFeature.urgency(waitedSeconds: 30) == 0)
    check("it grows with the wait", ActivitiesFeature.urgency(waitedSeconds: 300) > 0.4)
    check("and stops at full", ActivitiesFeature.urgency(waitedSeconds: 86_400) == 1)
    check(
        "urgency only ever rises",
        stride(from: 0.0, through: 900.0, by: 30.0).reduce((true, -1.0)) { carry, seconds in
            let value = ActivitiesFeature.urgency(waitedSeconds: seconds)
            return (carry.0 && value >= carry.1, value)
        }.0
    )
    check("a calm line breathes slowly", IslandPulse.period(urgency: 0) > IslandPulse.period(urgency: 1))
    check("and dims further than an urgent one", IslandPulse.floor(urgency: 0) < IslandPulse.floor(urgency: 1))
    check("it never becomes a flash", IslandPulse.period(urgency: 1) >= 0.7)

    // A question the notch can answer, and the token the answer is filed
    // under. It becomes a key in this app's own preferences, so it is held to
    // letters, digits and three punctuation marks, and anything else is refused
    // outright rather than trimmed — a half-accepted token would file an answer
    // where the asker is not looking, leaving it waiting for a reply already
    // given.
    check("a plain token is accepted", ActivitiesReader.safeToken("ask-9f2b7c") == "ask-9f2b7c")
    check("an empty one is not", ActivitiesReader.safeToken("") == nil)
    check("nor one with a space", ActivitiesReader.safeToken("ask 1") == nil)
    check("nor one that could be read as structure", ActivitiesReader.safeToken("a\"b") == nil)
    check("nor a path", ActivitiesReader.safeToken("../../etc/passwd") == nil)
    check(
        "nor one longer than the cap",
        ActivitiesReader.safeToken(String(repeating: "a", count: ActivitiesReader.maxTokenLength + 1)) == nil
    )
    check(
        "and one exactly at the cap is fine",
        ActivitiesReader.safeToken(String(repeating: "a", count: ActivitiesReader.maxTokenLength)) != nil
    )

    let asked = tempFile("""
    [
      {"id": "q", "title": "Allow Bash?", "asks": "ask-9f2b7c"},
      {"id": "r", "title": "Allow Bash?", "asks": "../nope"},
      {"id": "s", "title": "Just telling you"}
    ]
    """)
    let askedFeed = ActivitiesReader.read(from: asked)
    check("a question carries its token through the feed", askedFeed.first?.asks == "ask-9f2b7c")
    check("a bad token is dropped, the activity is not", askedFeed.dropFirst().first?.asks == nil)
    check("and an ordinary activity asks nothing", askedFeed.last?.asks == nil)

    // The letterbox the answer is left in. Preferences rather than a file,
    // deliberately — the app promises it writes none.
    let answers = InMemoryDefaults()
    check("nothing is answered to begin with", PermissionAnswers.decision(for: "ask-1", in: answers) == nil)
    PermissionAnswers.record(token: "ask-1", decision: .allow, to: answers)
    check("an answer can be collected", PermissionAnswers.decision(for: "ask-1", in: answers) == .allow)
    PermissionAnswers.record(token: "ask-2", decision: .deny, to: answers)
    check("and does not disturb another", PermissionAnswers.decision(for: "ask-1", in: answers) == .allow)
    check("the second stands on its own", PermissionAnswers.decision(for: "ask-2", in: answers) == .deny)
    check("an answer nobody gave is nothing", PermissionAnswers.decision(for: "ask-3", in: answers) == nil)

    // A letterbox, not a record of what you have allowed — that would be a log
    // of your decisions, which this app has no business keeping.
    var manyAnswers: [String: String] = [:]
    for index in 0..<40 { manyAnswers["ask-\(index)"] = "allow \(1_700_000_000 + index)" }
    let keptAnswers = PermissionAnswers.pruned(manyAnswers, limit: PermissionAnswers.limit)
    check("only the newest few answers are kept", keptAnswers.count == PermissionAnswers.limit)
    check("and it is the newest that are kept", keptAnswers["ask-39"] != nil && keptAnswers["ask-0"] == nil)
    PermissionAnswers.clear(in: answers)
    check("and they can all be cleared", PermissionAnswers.decision(for: "ask-1", in: answers) == nil)
    check("and never stops breathing altogether", IslandPulse.floor(urgency: 1) < 1)

    // A logo is drawn larger than a symbol — it has no disc around it, so the
    // room a badge spends on its disc is artwork instead, and a mark made of
    // fine lines needs every point of it to survive being drawn 40 pixels tall.
    // Bounded, because artwork that outgrows the strip would push the pill
    // taller than the shape it is meant to sit inside.
    check("a logo is drawn larger than a symbol", ActivitiesFeature.logoSide(for: 21) > 21)
    check("but never by much", ActivitiesFeature.logoSide(for: 21) <= 21 + 8)
    check("and the cap holds at any size", ActivitiesFeature.logoSide(for: 100) <= 108)
    check(
        "something waiting on you lights it too",
        ActivitiesFeature.tint(for: waitingAlert) != nil
    )
    check(
        "and the two do not look the same",
        ActivitiesFeature.tint(for: finishedAlert) != ActivitiesFeature.tint(for: waitingAlert)
    )
    // Work still going on is already described by the strip. Lighting the whole
    // island for it would spend the signal on something nobody has to act on.
    check(
        "work still in progress lights nothing",
        ActivitiesFeature.tint(for: workingAlert) == nil
    )
    check(
        "and an empty feed lights nothing",
        ActivitiesFeature.tint(for: nil) == nil
    )
    check(
        "an activity with no image still has its symbol",
        ActivitiesReader.read(from: tempFile("[{\"id\":\"S\",\"title\":\"Sym\",\"icon\":\"bolt.fill\"}]"))
            .first.map { $0.imagePath == nil && $0.icon == "bolt.fill" } == true
    )

    // The feed folder moved when the app was renamed, and the posters are other
    // programs that do not update when this app does. Reading only the new
    // folder would have made the whole feature go quiet on the first launch
    // after an update, with nothing on screen to say why.
    let feedHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-feed-\(UUID().uuidString)")
    let newFolder = feedHome.appendingPathComponent(".hashnotch")
    let oldFolder = feedHome.appendingPathComponent(".hashdisland")
    try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)

    check(
        "with neither folder written, the new one is where it looks",
        ActivitiesReader.feedURL(in: feedHome).path == newFolder.appendingPathComponent("activities.json").path
    )
    try? Data("[]".utf8).write(to: oldFolder.appendingPathComponent("activities.json"))
    check(
        "a poster still writing to the old folder is still read",
        ActivitiesReader.feedURL(in: feedHome).path == oldFolder.appendingPathComponent("activities.json").path
    )
    try? Data("[]".utf8).write(to: newFolder.appendingPathComponent("activities.json"))
    check(
        "a poster that has moved is never shadowed by the old file",
        ActivitiesReader.feedURL(in: feedHome).path == newFolder.appendingPathComponent("activities.json").path
    )
    try? FileManager.default.removeItem(at: feedHome)

    // The "quit?" window is exactly as tall as the words in it.
    //
    // It shipped with a hand-picked height and a Spacer holding the content
    // apart to reach it, which left a band of empty black between the last line
    // and the buttons — the kind of gap that reads as something having failed
    // to draw. The height is now measured from the laid-out view, so what is
    // pinned here is that the measurement is real: a view that has not been
    // arranged reports zero, and a window sized from zero is not small, it is
    // invisible.
    let quitHosting = NSHostingController(
        rootView: QuitConfirmationView(accent: .blue, onQuit: {}, onCancel: {})
    )
    quitHosting.view.layoutSubtreeIfNeeded()
    let quitFit = quitHosting.view.fittingSize
    check(
        "the quit window measures a real height, not zero",
        quitFit.height >= QuitConfirmation.minimumHeight
    )
    check(
        "the quit window is not padded out past what it says",
        quitFit.height <= QuitConfirmation.minimumHeight + 120
    )
    check(
        "the quit window keeps the one width it is designed for",
        abs(quitFit.width - QuitConfirmation.width) < 1
    )
    print("       quit window measures \(Int(quitFit.width))x\(Int(quitFit.height))")

    // And it opens in the MIDDLE of the screen, which `NSWindow.center()` does
    // not do: that method leaves about a third of the free space above the
    // window, which on a laptop parked this one under the physical notch, hard
    // against the top bezel and touching the island whose button raised it.
    let quitScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let quitSize = CGSize(width: QuitConfirmation.width, height: 204)
    let quitOrigin = QuitConfirmation.origin(for: quitSize, in: quitScreen)
    check(
        "the quit window is centred across the screen",
        abs((quitOrigin.x + quitSize.width / 2) - quitScreen.midX) < 0.5
    )
    check(
        "the quit window is centred DOWN the screen, not pushed to the top",
        abs((quitOrigin.y + quitSize.height / 2) - quitScreen.midY) < 0.5
    )
    // The same on a screen whose usable area does not start at zero — a Dock at
    // the bottom and a menu bar at the top both move the middle.
    let inset = CGRect(x: 0, y: 70, width: 1440, height: 900 - 70 - 38)
    let insetOrigin = QuitConfirmation.origin(for: quitSize, in: inset)
    check(
        "the middle is the middle of the space actually available",
        abs((insetOrigin.y + quitSize.height / 2) - inset.midY) < 0.5
    )
    check(
        "the whole window fits inside that space",
        insetOrigin.y >= inset.minY && insetOrigin.y + quitSize.height <= inset.maxY
    )

    // The outline traces three sides, never four.
    //
    // `NotchShape` is square across the top because the island has to meet the
    // screen edge without a seam — right for the black silhouette, wrong for a
    // line drawn along it. Stroking the closed shape ran the colour across the
    // top and turned it through two hard right angles, in the one place that is
    // not an edge at all: above it is bezel, or menu bar.
    //
    // Compared against the silhouette rather than against numbers, so the two
    // cannot drift apart: the outline must be shorter, and it must not reach
    // the top edge anywhere along its length.
    let outlineBox = CGRect(x: 0, y: 0, width: 200, height: 40)
    let traced = IslandOutlineShape(radius: 14).path(in: outlineBox)
    check(
        "the outline spans the island it belongs to",
        abs(traced.boundingRect.width - outlineBox.width) < 0.5
            && abs(traced.boundingRect.height - outlineBox.height) < 0.5
    )
    // A three-sided line does not run ACROSS the top, and the way to ask is to
    // look at the segments rather than at the filled region.
    //
    // `Path.contains` is the wrong instrument here and answers yes to
    // everything: it tests the area a path would FILL, and an open path is
    // implicitly closed for that test — so the missing top edge is imagined
    // back in and every interior point reads as covered. The line either exists
    // as a drawn segment or it does not.
    var segments: [(CGPoint, CGPoint)] = []
    var cursor = CGPoint.zero
    var subpathStart = CGPoint.zero
    traced.forEach { element in
        switch element {
        case .move(let to):
            cursor = to
            subpathStart = to
        case .line(let to):
            segments.append((cursor, to))
            cursor = to
        case .quadCurve(_, let to):
            segments.append((cursor, to))
            cursor = to
        case .curve(_, _, let to):
            segments.append((cursor, to))
            cursor = to
        case .closeSubpath:
            segments.append((cursor, subpathStart))
            cursor = subpathStart
        }
    }
    let top = outlineBox.minY
    check(
        "no segment runs along the top edge",
        !segments.contains { abs($0.0.y - top) < 0.5 && abs($0.1.y - top) < 0.5 }
    )
    // The two ends DO reach the top, one on each side — that is what lets them
    // be faded out under the bezel rather than stopping in mid-air.
    check(
        "but both ends reach up to it, one per side",
        segments.contains { abs($0.0.y - top) < 0.5 || abs($0.1.y - top) < 0.5 }
    )
    // And the shape is not closed back on itself, which is what would put that
    // top line back.
    check(
        "and the path never closes itself",
        !traced.description.lowercased().contains("z")
    )

    // The island's edge takes a colour from whichever feature holds the strip,
    // the way the iPhone lights its screen edge. The rule worth pinning is
    // restraint: a colour that appears for everything is decoration, and it
    // makes the ones that mean something invisible.
    check(
        "going on the charger lights the edge",
        BatteryFeature.tint(for: .pluggedIn(42)) != nil
    )
    check(
        "running out lights it a different colour",
        BatteryFeature.tint(for: .lowBattery(8)) != nil
            && BatteryFeature.tint(for: .lowBattery(8)) != BatteryFeature.tint(for: .pluggedIn(42))
    )
    check(
        "coming off the charger lights it too",
        BatteryFeature.tint(for: .unplugged(80)) != nil
    )
    check(
        "reaching full lights it as good news, like going on",
        BatteryFeature.tint(for: .fullyCharged(100)) == BatteryFeature.tint(for: .pluggedIn(42))
    )
    check(
        "running out does not look like running on battery",
        BatteryFeature.tint(for: .lowBattery(8)) != BatteryFeature.tint(for: .unplugged(80))
    )
    check(
        "every battery announcement carries a colour",
        [BatteryEvent.pluggedIn(1), .unplugged(1), .lowBattery(1), .fullyCharged(1)]
            .allSatisfy { BatteryFeature.tint(for: $0) != nil }
    )
    check(
        "and a quiet battery lights nothing at all",
        BatteryFeature.tint(for: nil) == nil
    )
    // A feature that has no opinion must not be made to have one: the default
    // is no colour, so adding a feature never changes what the edge does.
    check(
        "a feature with nothing to say leaves the edge alone",
        StubFeature(id: "quiet", placement: .leading).outlineTint == nil
    )

    // One island, or none. A second copy of this app doubles everything it
    // draws — two overlays on top of each other and every alert twice — with
    // nothing on screen to explain it, since there is no Dock icon or menu-bar
    // item to reveal that a copy is already up.
    check(
        "a copy never counts itself as another copy",
        SingleInstance.others().allSatisfy {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    )
    // The checks run unbundled, which is also how the app is worked on. An
    // unbundled build has no identifier, cannot be recognised as a copy, and
    // must never be refused a start over it.
    check(
        "an unbundled build is never refused a start",
        Bundle.main.bundleIdentifier != nil || SingleInstance.anotherCopyIsRunning == false
    )

    // An older copy under the app's previous name has to be recognisable.
    //
    // This is the fault that reads, from the screen, as the app losing every
    // setting on restart: the old bundle keeps its own preferences domain and
    // its own permissions, and macOS records "open at login" by file reference,
    // so the registration survives a rename and goes on opening the old one.
    // Nothing about it looks like a second app being installed.
    check(
        "the app knows the name it shipped under before this one",
        PreviousInstall.previousBundleIDs.contains("com.hashdisland.app")
    )
    check(
        "and does not count the current name as an older one",
        PreviousInstall.previousBundleIDs.contains(Bundle.main.bundleIdentifier ?? "com.hashnotch.app") == false
    )
    check(
        "every previous name is a real bundle identifier, not a display name",
        PreviousInstall.previousBundleIDs.allSatisfy {
            $0.hasPrefix("com.") && !$0.contains(" ") && $0.split(separator: ".").count >= 3
        }
    )
    // Whatever this Mac happens to have, asking must not throw or hang, and an
    // answer must describe the copy it found rather than a generality.
    if let foundOld = PreviousInstall.find() {
        check(
            "a copy that was found is described by where it actually is",
            foundOld.url.pathExtension == "app"
                && PreviousInstall.previousBundleIDs.contains(foundOld.bundleID)
        )
        print("       an older copy IS installed on this Mac: \(foundOld.url.path)")
    } else {
        check("no older copy is installed on this Mac, and asking is safe", true)
    }

    // A finished notice is the tool's name and nothing else.
    //
    // What posters put underneath it is which model answered — "gemini-2.5-flash"
    // trailing "HashCortX finished" — and on a strip that is read in a glance
    // that is debris: the work is over, so a second line offers nothing to act
    // on while costing the first line the room to be read cleanly. The app's own
    // Claude Code hook already sends no subtitle on a finish, but nothing it
    // does could make that true of anybody else's poster, so the rule is applied
    // where every poster passes through rather than asked of each one.
    let finishedNotice = ActivitiesReader.read(from: tempFile("""
    [{"id":"hashcortx","title":"HashCortX finished","subtitle":"gemini-2.5-flash",
      "dismissAfter":3,"endsAt":"2099-01-01T12:00:03Z"}]
    """))
    check("a finished notice is read as a notice", finishedNotice.first?.isNotice == true)
    check(
        "a finished notice shows the tool and not the model",
        finishedNotice.first.map { $0.title == "HashCortX finished" && $0.displaySubtitle == nil } == true
    )
    check(
        "the subtitle is still carried, only not drawn",
        finishedNotice.first?.subtitle == "gemini-2.5-flash"
    )
    // A standing request is the opposite case: there the subtitle IS the reason
    // it is asking, and dropping it would leave a notice that has withheld the
    // only part worth reading.
    let standingRequest = ActivitiesReader.read(from: tempFile("""
    [{"id":"claude-code","title":"Claude needs you","subtitle":"Allow this command?",
      "endsAt":"2099-01-01T12:03:00Z"}]
    """))
    check(
        "a standing request keeps the reason it is asking",
        standingRequest.first?.displaySubtitle == "Allow this command?"
    )
    try? FileManager.default.removeItem(at: logoDir)

    // A notice announces something that already happened, so it draws no
    // countdown and leaves on its own. A countdown still counts.
    let notices = tempFile("""
    [
      {"id": "n1", "title": "Claude finished", "dismissAfter": 3, "endsAt": "\(future)"},
      {"id": "n2", "title": "Food delivery", "endsAt": "\(future)"},
      {"id": "n3", "title": "Clamped low", "dismissAfter": 0.1, "endsAt": "\(future)"},
      {"id": "n4", "title": "Clamped high", "dismissAfter": 9000, "endsAt": "\(future)"}
    ]
    """)
    let noticed = ActivitiesReader.read(from: notices)
    func activity(_ id: String) -> LiveActivity? { noticed.first { $0.id == id } }
    check("a notice draws no countdown", activity("n1")?.showsCountdown == false)
    check("a notice reports no time left", activity("n1")?.secondsLeft(now: Date()) == nil)
    check("a countdown still counts down", activity("n2")?.showsCountdown == true)
    check("a countdown still reports time left", (activity("n2")?.secondsLeft(now: Date()) ?? 0) > 0)
    check("a too-short notice is clamped up", activity("n3")?.dismissAfter == 1)
    check("a too-long notice is clamped down", activity("n4")?.dismissAfter == 30)

    // The dismissal moment is measured from when the notice first appeared.
    let seen = Date()
    check(
        "a notice leaves after its own delay",
        activity("n1")?.dismissalDate(firstSeen: seen) == seen.addingTimeInterval(3)
    )
    check("a countdown never self-dismisses", activity("n2")?.dismissalDate(firstSeen: seen) == nil)
    try? FileManager.default.removeItem(at: notices)

    // The icon is a string from the same untrusted feed, so it is bounded like
    // every other field — and an absent or empty one still draws something.
    let icons = tempFile("""
    [
      {"id": "i1", "title": "Long icon", "icon": "\(String(repeating: "x", count: 500))"},
      {"id": "i2", "title": "Empty icon", "icon": ""},
      {"id": "i3", "title": "No icon"}
    ]
    """)
    let iconParsed = ActivitiesReader.read(from: icons)
    check("feed caps icon length", (iconParsed.first { $0.id == "i1" }?.icon.count ?? 999) <= 64)
    check("feed defaults empty icon", (iconParsed.first { $0.id == "i2" })?.icon == "app.badge")
    check("feed defaults missing icon", (iconParsed.first { $0.id == "i3" })?.icon == "app.badge")
    try? FileManager.default.removeItem(at: icons)

    // Token files: counts only today's assistant lines, each message id once,
    // ignores malformed ones, and keeps cache tokens out of the headline.
    let startOfToday = Calendar.current.startOfDay(for: Date())
    let todayStamp = ISO8601DateFormatter().string(from: Date())
    let oldStamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172_800))

    let claudeFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
    {"type":"assistant","timestamp":"\(oldStamp)","message":{"id":"m2","usage":{"input_tokens":999,"output_tokens":999}}}
    not json at all
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"usage":{"input_tokens":1,"output_tokens":2}}}
    {"type":"user","timestamp":"\(todayStamp)","message":{"id":"m9","usage":{"input_tokens":500,"output_tokens":500}}}
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m3","usage":{"input_tokens":10,"output_tokens":20}}}
    """)
    var seenIDs = SeenMessages()
    let claudeCounted = TokenUsageReader.tokens(inClaudeFile: claudeFile, since: startOfToday, seen: &seenIDs)
    // Processed tokens (input + cache-write + output), each message once:
    // m1 = 100+200+50, the no-id line = 1+2, m3 = 10+20.
    check("claude counts processed tokens once per message", claudeCounted.io == 383)
    check("claude separates cache reads", claudeCounted.cache == 1000)
    check("claude ignores non-assistant lines", seenIDs.count == 2 && seenIDs.contains("m1") && seenIDs.contains("m3") && !seenIDs.contains("m9"))

    // The same message id appearing in ANOTHER file (continued session) must
    // also be skipped — the seen-set spans the whole scan.
    let continuedFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50}}}
    """)
    check("claude dedups across files", TokenUsageReader.tokens(inClaudeFile: continuedFile, since: startOfToday, seen: &seenIDs).io == 0)
    try? FileManager.default.removeItem(at: claudeFile)
    try? FileManager.default.removeItem(at: continuedFile)

    let ecosystemFile = tempFile("""
    {"ts":"\(todayStamp)","input_tokens":10,"output_tokens":5,"cache_read":100,"cache_write":20}
    {"ts":"\(oldStamp)","input_tokens":7,"output_tokens":7}
    """)
    let ecosystemCounted = TokenUsageReader.tokens(inEcosystemFile: ecosystemFile, since: startOfToday)
    // Processed = 10+5+20 (cache_write counts, cache_read does not).
    check("ecosystem counts processed tokens", ecosystemCounted.io == 35)
    check("ecosystem separates cache reads", ecosystemCounted.cache == 100)
    try? FileManager.default.removeItem(at: ecosystemFile)

    // A file larger than one read chunk (1 MB) exercises the streaming path's
    // carry-over of partial lines across chunk boundaries.
    let padding = String(repeating: "x", count: 400)
    let bigLines = (0..<4000).map {
        "{\"type\":\"assistant\",\"timestamp\":\"\(todayStamp)\",\"pad\":\"\(padding)\",\"message\":{\"id\":\"big-\($0)\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}"
    }
    let bigFile = tempFile(bigLines.joined(separator: "\n"))
    var bigSeen = SeenMessages()
    check("streaming counts across chunk boundaries", TokenUsageReader.tokens(inClaudeFile: bigFile, since: startOfToday, seen: &bigSeen).io == 4000)
    try? FileManager.default.removeItem(at: bigFile)

    // A line with no newline in sight is a corrupt file, not a usage record: it
    // is dropped rather than buffered without limit, and the valid lines around
    // it still count.
    let monsterLine = "{\"pad\":\"\(String(repeating: "x", count: 9 << 20))\"}"
    let monsterFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"before","usage":{"input_tokens":7,"output_tokens":0}}}
    \(monsterLine)
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"after","usage":{"input_tokens":3,"output_tokens":0}}}
    """)
    var monsterSeen = SeenMessages()
    let monsterCounted = TokenUsageReader.tokens(inClaudeFile: monsterFile, since: startOfToday, seen: &monsterSeen)
    check("streaming drops an unbounded line", monsterCounted.io == 10)
    check("streaming resumes after a dropped line", monsterSeen.contains("before") && monsterSeen.contains("after"))
    try? FileManager.default.removeItem(at: monsterFile)

    // Deciding whether a line is from today, without building a Date for every
    // one of them. The timestamps are UTC and the day wanted is local, so these
    // are different days for part of every 24 hours — which is why the fast
    // path is a three-way comparison and not an equality test.
    let dayPrefix = TokenUsageReader.utcDayPrefix(of: startOfToday)
    check(
        "a timestamp from an earlier day is rejected without parsing",
        TokenUsageReader.isAtOrAfter(
            "1999-01-01T00:00:00Z", since: startOfToday, utcDayPrefix: dayPrefix
        ) == false
    )
    check(
        "a timestamp from a later day is accepted without parsing",
        TokenUsageReader.isAtOrAfter(
            "2999-01-01T00:00:00Z", since: startOfToday, utcDayPrefix: dayPrefix
        )
    )
    check(
        "a timestamp on the boundary day is judged on the real instant",
        TokenUsageReader.isAtOrAfter(
            ISO8601DateFormatter().string(from: startOfToday.addingTimeInterval(-1)),
            since: startOfToday, utcDayPrefix: dayPrefix
        ) == false
    )
    check(
        "an instant just after the boundary is kept",
        TokenUsageReader.isAtOrAfter(
            ISO8601DateFormatter().string(from: startOfToday.addingTimeInterval(60)),
            since: startOfToday, utcDayPrefix: dayPrefix
        )
    )
    check(
        "a missing or truncated timestamp is not today",
        TokenUsageReader.isAtOrAfter(nil, since: startOfToday, utcDayPrefix: dayPrefix) == false
            && TokenUsageReader.isAtOrAfter("2026", since: startOfToday, utcDayPrefix: dayPrefix) == false
    )

    // The scanner reads only what has been appended since it last looked. This
    // is the difference between a poll costing tens of megabytes and costing
    // nothing, so what is pinned here is that resuming counts the SAME total a
    // full re-read would — and that the ways a file can betray an offset are
    // each noticed.
    let scanRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-scan-\(UUID().uuidString)")
    let scanProjects = scanRoot.appendingPathComponent("projects/one")
    try? FileManager.default.createDirectory(at: scanProjects, withIntermediateDirectories: true)
    let transcript = scanProjects.appendingPathComponent("session.jsonl")

    func assistantLine(_ id: String, _ input: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(todayStamp)\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":0}}}\n"
    }
    func writeTranscript(_ text: String) {
        try? text.data(using: .utf8)?.write(to: transcript)
    }
    func appendTranscript(_ text: String) {
        guard let handle = try? FileHandle(forWritingTo: transcript) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    }

    writeTranscript(assistantLine("a", 10) + assistantLine("b", 20))
    let scanner = TokenUsageScanner(
        claudeProjects: scanRoot.appendingPathComponent("projects"),
        ecosystemFiles: []
    )
    check("the scanner counts a transcript it has not seen", scanner.readToday().claude == 30)

    let bytesAfterFirst = scanner.lastBytesRead
    check("the first pass actually read the file", bytesAfterFirst > 0)
    check("a second look at an unchanged file reads nothing at all", {
        _ = scanner.readToday()
        return scanner.lastBytesRead == 0
    }())
    check("and reports the same total", scanner.readToday().claude == 30)

    appendTranscript(assistantLine("c", 5))
    let afterAppend = scanner.readToday()
    check("an appended message is added to the running total", afterAppend.claude == 35)
    check(
        "only the appended bytes were read",
        scanner.lastBytesRead > 0 && scanner.lastBytesRead < bytesAfterFirst
    )

    // A message that streams is rewritten under the same id. Resuming must not
    // count it twice, which is the whole reason the seen-set cannot be thrown
    // away between polls.
    appendTranscript(assistantLine("c", 5))
    check("a message rewritten as it streams is still counted once", scanner.readToday().claude == 35)

    // A tail with no newline is a line still being written. It must not be
    // counted as a fragment, and must be counted in full once it lands.
    appendTranscript("{\"type\":\"assistant\",\"timestamp\":\"\(todayStamp)\",\"message\":{\"id\":\"d\",\"usa")
    check("a half-written line is not counted", scanner.readToday().claude == 35)
    appendTranscript("ge\":{\"input_tokens\":7,\"output_tokens\":0}}}\n")
    check("and it counts in full once the rest arrives", scanner.readToday().claude == 42)

    // Truncation and replacement both mean a remembered offset now points into
    // the wrong place. The seen-set is shared across every transcript, so one
    // file's contribution cannot be withdrawn on its own — the day is counted
    // again instead, which cannot be subtly wrong.
    writeTranscript(assistantLine("x", 3))
    check("a file that shrank is counted again rather than resumed", scanner.readToday().claude == 3)

    // A whole re-read must agree with what the incremental passes accumulated.
    writeTranscript(assistantLine("a", 10) + assistantLine("b", 20) + assistantLine("c", 5))
    let fresh = TokenUsageScanner(
        claudeProjects: scanRoot.appendingPathComponent("projects"),
        ecosystemFiles: []
    )
    scanner.reset()
    check(
        "resuming and reading whole arrive at the same number",
        scanner.readToday().claude == fresh.readToday().claude
    )

    // A new day is a different question, not more of the same one.
    let tomorrow = Date().addingTimeInterval(86_400)
    check(
        "yesterday's count does not carry into a new day",
        scanner.readToday(now: tomorrow).claude == 0
    )
    try? FileManager.default.removeItem(at: scanRoot)

    // The remembered totals exist so the panel opens on a number rather than on
    // a zero it has not earned. A remembered number from ANOTHER day is not a
    // stale figure to be corrected — it is a different question's answer.
    let cacheDefaults = InMemoryDefaults()
    var remembered = TokenTotals()
    remembered.claude = 1234
    TokenTotalsCache.save(remembered, to: cacheDefaults)
    check(
        "today's totals are remembered across a launch",
        TokenTotalsCache.load(from: cacheDefaults)?.totals.claude == 1234
    )
    check(
        "totals from another day are discarded rather than shown",
        TokenTotalsCache.load(now: tomorrow, from: cacheDefaults) == nil
    )
    TokenTotalsCache.clear(in: cacheDefaults)
    check("clearing the remembered totals leaves nothing", TokenTotalsCache.load(from: cacheDefaults) == nil)

    // "Only when I ask" must mean no clock at all, and every other choice must
    // name a real period.
    check("the never option runs on no schedule", TokenScanInterval.never.seconds == nil)
    check(
        "every other scan interval is a real period",
        TokenScanInterval.allCases
            .filter { $0 != .never }
            .allSatisfy { ($0.seconds ?? 0) > 0 }
    )
    // The picker is drawn in `allCases` order, so that order IS the list
    // somebody reads. Ascending, with "only when I ask" last, because it is
    // the one that is not a period at all.
    check(
        "the intervals are offered shortest first",
        zip(
            TokenScanInterval.allCases.filter { $0 != .never },
            TokenScanInterval.allCases.filter { $0 != .never }.dropFirst()
        ).allSatisfy { ($0.seconds ?? 0) < ($1.seconds ?? 0) }
    )
    check("and only when I ask comes last", TokenScanInterval.allCases.last == .never)
    check("every interval says what it is", TokenScanInterval.allCases.allSatisfy {
        !$0.label.isEmpty
    })
    // The short end exists because the count is no longer gated on the panel
    // being open, so what is picked here is genuinely how often the figure is
    // brought up to date.
    check("the shortest choice is ten seconds",
          TokenScanInterval.allCases.first?.seconds == 10)

    // Low-battery announcements fire exactly when a threshold is crossed
    // downward, never on charge or within a band.
    check("low fires crossing 20", BatteryMonitor.crossedLowThreshold(from: 21, to: 20) == 20)
    check("low fires crossing 10", BatteryMonitor.crossedLowThreshold(from: 15, to: 9) == 10)
    check("low silent inside band", BatteryMonitor.crossedLowThreshold(from: 19, to: 15) == nil)
    check("low silent when rising", BatteryMonitor.crossedLowThreshold(from: 9, to: 30) == nil)

    // Being on power and being charged by it are different facts. The state a
    // Mac is hardest to catch in — plugged in, parked at 80% by optimised
    // charging, deliberately not charging — is the one that must not claim to
    // be charging, so every combination is pinned here rather than waited for.
    check(
        "unplugged is discharging",
        BatteryMonitor.state(onPower: false, isCharging: false, percentage: 64) == .discharging
    )
    check(
        "plugged in and filling is charging",
        BatteryMonitor.state(onPower: true, isCharging: true, percentage: 64) == .charging
    )
    check(
        "plugged in and full is charged",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 100) == .charged
    )
    check(
        "plugged in and parked at 80 is on hold, not charging",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 80) == .onHold
    )
    check(
        "a full battery still reads charged just under 100",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 96) == .charged
    )
    check(
        "power state alone never implies charging",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 50) != .charging
    )

    // Only the low-battery warning earns the longer stay on the notch.
    check("a low warning is a warning", BatteryEvent.lowBattery(10).isWarning)
    check("plugging in is not a warning", BatteryEvent.pluggedIn(50).isWarning == false)

    // An announcement's symbol belongs to the announcement, not to whatever the
    // battery is doing while it is on screen. The view used to ask the live
    // state, and macOS reports external power a beat BEFORE it reports
    // charging — so at the instant a cable went in the state was "on hold" and
    // plugging in was announced with a pause symbol, every time, on a Mac that
    // then charged perfectly normally.
    check(
        "plugging in always shows the bolt",
        BatteryEvent.pluggedIn(50).symbolName == "bolt.fill"
    )
    check(
        "and it shows the same bolt at every level",
        [0, 50, 79, 80, 99, 100].allSatisfy { BatteryEvent.pluggedIn($0).symbolName == "bolt.fill" }
    )
    // Unplugging used to draw a PLUG, which names the thing that just left — at
    // a glance that reads as "there is a charger here", the opposite of what
    // happened. It shows a battery now, filled to where the battery actually
    // is, so the symbol and the number beside it never disagree.
    check(
        "unplugging shows a battery, not a plug",
        BatteryEvent.unplugged(50).symbolName.hasPrefix("battery.")
    )
    check(
        "and the battery it shows matches the level",
        BatteryEvent.unplugged(5).symbolName == "battery.0percent"
            && BatteryEvent.unplugged(50).symbolName == "battery.50percent"
            && BatteryEvent.unplugged(100).symbolName == "battery.100percent"
    )
    check(
        "every level has a battery to draw",
        (0...100).allSatisfy { BatteryEvent.unplugged($0).symbolName.hasPrefix("battery.") }
    )

    // The dividing lines between indicators are the reader's to set — including
    // all the way off, which is a preference rather than a broken state.
    check(
        "the dividing lines can be turned off entirely",
        AppearanceSettings.separatorThicknessRange.lowerBound == 0
    )
    check(
        "and never drawn thick enough to become a row of their own",
        AppearanceSettings.separatorThicknessRange.upperBound <= 4
            && AppearanceSettings.separatorOpacityRange.upperBound <= 0.5
    )
    check(
        "the shipped default is a visible hairline",
        AppearanceSettings().separatorThickness > 0
            && AppearanceSettings().separatorOpacity > 0
    )
    // A default sitting at the end of its own slider can only be moved one way,
    // which makes the control look broken to anyone who tries the wrong
    // direction first.
    check(
        "the shipped lines can be made both fainter and stronger",
        AppearanceSettings.separatorOpacityRange.contains(AppearanceSettings().separatorOpacity)
            && AppearanceSettings().separatorOpacity > AppearanceSettings.separatorOpacityRange.lowerBound
            && AppearanceSettings().separatorOpacity < AppearanceSettings.separatorOpacityRange.upperBound
    )
    check(
        "and both thinner and thicker",
        AppearanceSettings().separatorThickness > AppearanceSettings.separatorThicknessRange.lowerBound
            && AppearanceSettings().separatorThickness < AppearanceSettings.separatorThicknessRange.upperBound
    )

    // The shipped defaults are the arrangement the app was actually tuned on,
    // not whatever fell out of the order things were written in.
    // ── The microphone readout ───────────────────────────────────────────────
    //
    // This one asks the system a single boolean per audio process — "is this
    // one running an input stream" — and never opens audio, so there is no
    // microphone permission and nothing to listen with. The checks below cover
    // the parts that can be checked without a call running.
    check("a call under a minute reads as seconds", CallReader.elapsedText(42) == "0:42")
    check("a minute is a minute", CallReader.elapsedText(60) == "1:00")
    check("a long meeting reads in minutes", CallReader.elapsedText(2_705) == "45:05")
    check("past an hour it grows an hours field", CallReader.elapsedText(3_661) == "1:01:01")
    check("a negative duration cannot appear", CallReader.elapsedText(-5) == "0:00")
    // Nothing is playing or recording during a checks run, and Apple's own
    // dictation service holds an input stream open on an ordinary Mac — so a
    // reader that counted every process would report a call right now. Only
    // real applications count, which is what excludes it.
    check(
        "a system service holding the microphone is not a call",
        CallReader.allListeners().allSatisfy { !$0.bundleIdentifier.isEmpty }
    )
    check(
        "and every listener it does report is a named app",
        CallReader.allListeners().allSatisfy { !$0.name.isEmpty }
    )
    // FaceTime does not hold the microphone itself — `avconferenced` holds it
    // on FaceTime's behalf — so the readout said "avconferenced" during a
    // FaceTime call, which is true about the machine and useless about the
    // call. Whatever is reported must be something a person recognises.
    check(
        "nothing is ever reported by a daemon's internal name",
        CallReader.current().map { listener in
            listener.isNamedApp || listener.name == "Microphone in use"
        } ?? true
    )
    check(
        "an unattributed microphone still reports that it is live",
        {
            // Constructed rather than staged: a background service holding the
            // input is real and worth showing, it just cannot be named.
            let unnamed = CallReader.Listener(
                bundleIdentifier: "com.apple.somedaemon",
                name: "Microphone in use",
                processID: 1,
                isNamedApp: false
            )
            return unnamed.isNamedApp == false && !unnamed.name.isEmpty
        }()
    )

    // A locked Mac is the one moment none of this should be readable: what you
    // are listening to, which app has your microphone, what you have spent on
    // AI today. macOS puts the login window above ordinary windows, so the
    // island is already covered in practice — but covered is not the same as
    // absent, and this is the claim where that difference matters.
    check(
        "locking and unlocking are watched under the names macOS uses",
        PowerCoordinator.lockedNotification == "com.apple.screenIsLocked"
            && PowerCoordinator.unlockedNotification == "com.apple.screenIsUnlocked"
    )

    check("the accent everyone starts on is orange", AccentColor.default.id == "orange")
    // The panel hangs off a notch that is solid black. Anything translucent
    // makes the join visible — the notch stays black while the panel picks up
    // the wallpaper — and the illusion that the hardware opened is what the
    // whole design is paying for.
    check("the panel starts solid, so it matches the notch", AppearanceSettings().panelFill == .solid)

    // A graph with nothing to plot yet must still LOOK like a graph.
    //
    // Two points are needed for a shape, and below that the sparkline drew
    // nothing at all — no line, no fill, just empty space where a graph
    // belongs, which a reader cannot tell apart from the graph being switched
    // off. That is precisely what a fresh launch looks like, because the
    // readouts that live in the panel only sample while the panel is open: open
    // it for the first time and the internet graph is simply absent. It reads
    // as "graphs are not on by default" when they are, and sends people into
    // Settings to switch on something already switched on.
    check(
        "a graph with no samples yet still draws its baseline",
        Sparkline.showsBaselineOnly(sampleCount: 0)
    )
    check(
        "and so does one with a single sample",
        Sparkline.showsBaselineOnly(sampleCount: 1)
    )
    check(
        "two samples are enough to draw the real shape",
        Sparkline.showsBaselineOnly(sampleCount: 2) == false
    )
    // The default order is a value in the core, and the manifest sorts itself
    // by it — so adding a feature to the manifest cannot silently rearrange
    // everybody's panel, and this pins the arrangement itself.
    check(
        "a fresh install shows the indicators in the arranged order",
        FeatureRegistry.defaultOrder == [
            // The microphone leads. It is the only readout about something you
            // might have forgotten was happening, and the one worth seeing
            // before anything else on the panel.
            "call",
            "media", "activities", "downloads",
            "network", "battery", "airpods",
            "tokens", "thermal", "memory", "cpu",
            "timer", "storage",
        ]
    )
    // Applying it is what makes the manifest's own order irrelevant. Fed
    // deliberately backwards.
    check(
        "features are arranged whatever order they are registered in", {
            let shuffled: [NotchFeature] = [
                StubFeature(id: "storage", placement: .expanded),
                StubFeature(id: "media", placement: .leading),
                StubFeature(id: "battery", placement: .trailing),
            ]
            return FeatureRegistry.inDefaultOrder(shuffled).map(\.id) == ["media", "battery", "storage"]
        }()
    )
    // A feature nobody has placed yet goes to the end rather than to the front,
    // so adding one never displaces what people are used to.
    check(
        "an unlisted feature goes to the end", {
            let withNew: [NotchFeature] = [
                StubFeature(id: "brandnew", placement: .expanded),
                StubFeature(id: "media", placement: .leading),
            ]
            return FeatureRegistry.inDefaultOrder(withNew).map(\.id) == ["media", "brandnew"]
        }()
    )
    // Each feature's FIRST style is what a fresh install gets, so the options
    // are listed with the intended default at the front rather than sorted.
    check(
        "each indicator starts on its intended style",
        NetworkFeature().displayOptions.first?.id == "graph"
            && BatteryFeature().displayOptions.first?.id == "iconAndPercent"
            && TokensFeature().displayOptions.first?.id == "number"
            && ThermalFeature().displayOptions.first?.id == "symbolAndNumber"
            && MemoryFeature().displayOptions.first?.id == "numberAndGraph"
            && CPUFeature().displayOptions.first?.id == "numberAndGraph"
    )
    // Five minutes, not thirty.
    //
    // Thirty was chosen while the count only ran with the panel open, where it
    // meant "at most once per look" and the number was refreshed by the act of
    // looking. Now that it runs on its own clock, thirty would mean the figure
    // on the strip can be half an hour behind — and the premise the old default
    // rested on is gone with the gating.
    check(
        "the token count starts on a five-minute rhythm",
        SettingsStore.defaultTokenScanInterval == .fiveMinutes
    )

    // Plugging in a USB-C charger is not one clean transition: while the
    // adapter negotiates, macOS can report power arriving, dropping and
    // arriving again within a second or two, and each crossing looked like
    // news — so "Charger connected" appeared twice in a row. The physical event
    // happened once; the reporting of it stuttered.
    check(
        "two plug-ins are the same kind of announcement",
        BatteryEvent.pluggedIn(41).isSameKind(as: BatteryEvent.pluggedIn(42))
    )
    check(
        "plugging in and unplugging are not",
        BatteryEvent.pluggedIn(50).isSameKind(as: BatteryEvent.unplugged(50)) == false
    )
    // The level is deliberately not compared: it may well have ticked between
    // two reports of one event, and a repeat is a repeat whatever number rode
    // along with it.
    check(
        "a repeat is judged by kind, not by the level it carries",
        BatteryEvent.lowBattery(20).isSameKind(as: BatteryEvent.lowBattery(19))
            && BatteryEvent.fullyCharged(100).isSameKind(as: BatteryEvent.lowBattery(100)) == false
    )
    check(
        "every announcement has a symbol of its own",
        Set([
            BatteryEvent.pluggedIn(50).symbolName,
            BatteryEvent.lowBattery(10).symbolName,
            BatteryEvent.fullyCharged(100).symbolName,
            BatteryEvent.unplugged(50).symbolName,
        ]).count == 4
    )
    check("fully charged is not a warning", BatteryEvent.fullyCharged(100).isWarning == false)
    check("unplugging is not a warning", BatteryEvent.unplugged(80).isWarning == false)

    // Plugging in announces on the POWER transition, not on reaching the
    // charging state. macOS reports external power the instant the cable goes
    // in while IsCharging is still false, so the real sequence is
    // discharging → held → charging. Keying the announcement on "reached
    // charging" matched none of it, and the plug-in alert never fired while
    // unplugging — which has no such in-between step — announced every time.
    func announces(from previous: BatteryState, to next: BatteryState) -> String? {
        guard previous != next else { return nil }
        let wasOnPower = previous != .discharging
        let isOnPower = next != .discharging
        if isOnPower != wasOnPower { return isOnPower ? "pluggedIn" : "unplugged" }
        if previous == .charging, next == .charged || next == .onHold { return "fullyCharged" }
        return nil
    }
    check(
        "the cable going in announces even when charging has not begun yet",
        announces(from: .discharging, to: .onHold) == "pluggedIn"
    )
    check(
        "plugging in straight into a charge announces once",
        announces(from: .discharging, to: .charging) == "pluggedIn"
    )
    check(
        "plugging in at full announces",
        announces(from: .discharging, to: .charged) == "pluggedIn"
    )
    check(
        "settling from held into charging does not announce again",
        announces(from: .onHold, to: .charging) == nil
    )
    check(
        "pulling the cable announces",
        announces(from: .charging, to: .discharging) == "unplugged"
    )
    check(
        "finishing the charge announces",
        announces(from: .charging, to: .charged) == "fullyCharged"
    )
    check(
        "a health hold at the end of a charge announces",
        announces(from: .charging, to: .onHold) == "fullyCharged"
    )
    check("nothing changed, nothing announced", announces(from: .charging, to: .charging) == nil)

    // Charge speed is judged on the adapter's own rating, and claims nothing
    // when the adapter reports none.
    check("a phone charger is slow", BatteryMonitor.ChargeSpeed.forWatts(12) == .slow)
    check("20W is where a charger stops being a phone charger", BatteryMonitor.ChargeSpeed.forWatts(20) == .standard)
    // 29 and 30 are both real Apple adapters and both the stock supply for a
    // laptop this size. Calling either of them slow, for want of being the
    // biggest one sold, would be wrong about a charger doing its job.
    check("a 29W adapter is not slow", BatteryMonitor.ChargeSpeed.forWatts(29) == .standard)
    check("a 30W adapter is not slow", BatteryMonitor.ChargeSpeed.forWatts(30) == .standard)
    check("an everyday adapter is standard", BatteryMonitor.ChargeSpeed.forWatts(35) == .standard)
    check("a big adapter is fast", BatteryMonitor.ChargeSpeed.forWatts(96) == .fast)
    check("the fast threshold is 60W", BatteryMonitor.ChargeSpeed.forWatts(60) == .fast)
    check("no rating claims no speed", BatteryMonitor.ChargeSpeed.forWatts(0) == nil)

    // After the cable moves, the app keeps re-reading until there is nothing
    // left to wait for. A fixed burst was the wrong shape: charging can begin a
    // second or a minute after the cable goes in, and macOS may take several
    // minutes to estimate a time to full — its own menu says "no estimate"
    // meanwhile. Stopping on a clock left the panel holding its first
    // impression, which is how "held for battery health" survived on screen
    // while the menu bar said charging.
    check(
        "on battery there is nothing to wait for",
        BatteryMonitor.isSettled(state: .discharging, minutesToFull: nil)
    )
    check(
        "a full battery is settled",
        BatteryMonitor.isSettled(state: .charged, minutesToFull: nil)
    )
    check(
        "charging without an estimate keeps watching",
        BatteryMonitor.isSettled(state: .charging, minutesToFull: nil) == false
    )
    check(
        "charging with an estimate is settled",
        BatteryMonitor.isSettled(state: .charging, minutesToFull: 89)
    )
    check(
        "a hold keeps watching, in case it is only the adapter negotiating",
        BatteryMonitor.isSettled(state: .onHold, minutesToFull: nil) == false
    )

    // The charge ceiling is learned from behaviour, because macOS publishes no
    // way to ask. A Mac on power that has deliberately stopped short of full
    // has shown you its limit.
    check(
        "a hold below full teaches the ceiling",
        BatteryMonitor.ceiling(after: .onHold, percentage: 80, known: nil) == 80
    )
    check(
        "any limit is learned, not just eighty",
        BatteryMonitor.ceiling(after: .onHold, percentage: 60, known: nil) == 60
    )
    check(
        "a Mac sitting at 99 has finished, not been limited",
        BatteryMonitor.ceiling(after: .onHold, percentage: 99, known: nil) == nil
    )
    check(
        "charging below a known ceiling keeps it",
        BatteryMonitor.ceiling(after: .charging, percentage: 62, known: 80) == 80
    )
    check(
        "climbing past the ceiling unlearns it",
        BatteryMonitor.ceiling(after: .charging, percentage: 88, known: 80) == nil
    )
    check(
        "reaching full clears any ceiling",
        BatteryMonitor.ceiling(after: .charged, percentage: 100, known: 80) == nil
    )
    check(
        "unplugging changes nothing about the ceiling",
        BatteryMonitor.ceiling(after: .discharging, percentage: 47, known: 80) == 80
    )

    // Time is then counted to that level rather than to a full battery it will
    // never reach.
    check(
        "the estimate is scaled to the ceiling",
        // 51 points of climb left to full in 102 minutes is 2 min per point;
        // the 31 points up to 80% should read as about an hour.
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: 80) == 62
    )
    check(
        "no ceiling means the estimate is left alone",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: nil) == nil
    )
    check(
        "a ceiling of 100 is not a ceiling",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: 100) == nil
    )
    check(
        "already at the ceiling means nothing left to count",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 80, ceiling: 80) == nil
    )
    check(
        "no estimate to scale, no answer invented",
        BatteryMonitor.minutesToCeiling(minutesToFull: nil, percentage: 49, ceiling: 80) == nil
    )
    check(
        "a sliver of climb left never rounds down to nothing",
        // 10 minutes of climb spread over 21 points, of which one is wanted,
        // comes to under half a minute — which must still read as a minute
        // rather than as no time at all.
        BatteryMonitor.minutesToCeiling(minutesToFull: 10, percentage: 79, ceiling: 80) == 1
    )

    // A label drawn ON the accent has to stay readable, and White is one of
    // the accents on offer — which made the timer's Start button an empty
    // capsule. Judged on perceived brightness so an accent added later is
    // handled without anyone remembering this rule exists.
    check("white is a light accent", AccentColor.named("white").isLight)
    check("blue is not", AccentColor.named("blue").isLight == false)
    // Green looked like it should take white text and does not: white on that
    // green is about 1.75:1, black about 12:1. Trusting the arithmetic over the
    // impression is the entire reason this is computed rather than listed.
    check("green needs dark text too", AccentColor.named("green").isLight)
    check("purple is not", AccentColor.named("purple").isLight == false)
    check("orange is light enough to need dark text", AccentColor.named("orange").isLight)

    // Every style a feature offers must be one the panel can actually render.
    // The display styles were inert for a long time — the panel draws only the
    // expanded view, and none of those took a style — so a setting that changed
    // nothing sat in the Indicators list for every one of them.
    let styleFeatures: [(String, [String])] = [
        ("network", ["graph", "both", "downloadOnly", "uploadOnly", "stacked", "compact"]),
        ("battery", ["iconAndPercent", "percent", "icon", "timeRemaining"]),
        ("thermal", ["symbolAndNumber", "number", "word", "symbol"]),
        ("tokens", ["number", "labeled"]),
        ("cpu", ["numberAndGraph", "number", "graph"]),
    ]
    // Built here rather than read from the app's manifest, which lives in the
    // executable and is not importable.
    let manifest: [NotchFeature] = [
        NetworkFeature(), BatteryFeature(), ThermalFeature(), TokensFeature(), CPUFeature(),
    ]
    var everyOptionIsKnown = true
    for (id, known) in styleFeatures {
        guard let feature = manifest.first(where: { $0.id == id }) else { everyOptionIsKnown = false; continue }
        for option in feature.displayOptions where !known.contains(option.id) {
            everyOptionIsKnown = false
        }
    }
    check("every offered display style is one the panel knows", everyOptionIsKnown)
    check(
        "the features that offer styles are the ones expected to",
        Set(manifest.filter { !$0.displayOptions.isEmpty }.map(\.id))
            == Set(styleFeatures.map(\.0))
    )

    // Temperature can be read as a word instead of a number.
    check("a cool die reads Cool", ThermalWording.word(for: 42) == "Cool")
    check("a working die reads Warm", ThermalWording.word(for: 62) == "Warm")
    check("a hot die reads Hot", ThermalWording.word(for: 78) == "Hot")
    check("a very hot die says so", ThermalWording.word(for: 95) == "Very hot")

    // Sensor names come off the hardware cryptic and plentiful; the panel shows
    // a handful of categories with the hottest reading in each. This is pure so
    // it can run on the reading queue rather than on the thread drawing the
    // panel, which is where the whole sweep used to happen every three seconds.
    let groupedSensors = ThermalMonitor.grouped([
        ("PMU tdie3", 51),
        ("PMU tdie7", 58),
        ("GPU sensor", 44),
        ("NAND CH0 temp", 36),
        ("gas gauge battery", 31),
    ])
    check("sensors collapse into friendly categories", groupedSensors.count == 4)
    check("the hottest category leads", groupedSensors.first?.celsius == 58)
    check(
        "several readings of one part keep the hottest",
        groupedSensors.first(where: { $0.name == "Processor" })?.celsius == 58
    )
    check(
        "no sensors at all reads as empty rather than as zero",
        ThermalMonitor.grouped([]).isEmpty
    )

    // Memory in use is the figure Activity Monitor calls Memory Used, because a
    // readout that disagrees with the tool people already check is one they will
    // distrust whichever is the more defensible. App memory is the internal
    // pages minus the ones the system may throw away, plus wired, plus
    // compressed — free memory and the file cache are available to whatever asks
    // next, and counting them is what makes some readouts claim a Mac is
    // permanently full.
    check(
        "memory in use is app plus wired plus compressed",
        MemoryReader.usedBytes(
            internalPages: 100, purgeablePages: 20, wiredPages: 30,
            compressedPages: 10, pageSize: 16384
        ) == (100 - 20 + 30 + 10) * 16384
    )
    check(
        "purgeable pages are not counted as in use",
        MemoryReader.usedBytes(
            internalPages: 100, purgeablePages: 100, wiredPages: 0,
            compressedPages: 0, pageSize: 16384
        ) == 0
    )
    // The counters come from a struct that is not written atomically, so
    // purgeable can momentarily read higher than internal. Unsigned subtraction
    // would wrap that into an enormous number and the panel would report a Mac
    // using several exabytes.
    check(
        "a counter that reads backwards cannot wrap into a huge number",
        MemoryReader.usedBytes(
            internalPages: 10, purgeablePages: 999, wiredPages: 1,
            compressedPages: 0, pageSize: 16384
        ) == 16384
    )
    check(
        "a machine reporting no memory divides by nothing rather than crashing",
        MemorySnapshot(usedBytes: 5, totalBytes: 0).fraction == 0
    )
    check(
        "the fraction is what is in use over what there is",
        MemorySnapshot(usedBytes: 8_000_000_000, totalBytes: 16_000_000_000).fraction == 0.5
    )
    check(
        "more in use than exists is never reported",
        MemorySnapshot(usedBytes: 99, totalBytes: 10).fraction == 1
    )
    // And the real reading has to work on whatever Mac is running the checks.
    let liveMemory = MemoryReader.read()
    check("memory reads a real total from this Mac", (liveMemory?.totalBytes ?? 0) > 0)
    check(
        "and never reports more in use than the Mac holds",
        liveMemory.map { $0.usedBytes <= $0.totalBytes } ?? false
    )

    // The disk's temperature is called Drive, because the panel has a Storage
    // section of its own for how full it is and two unrelated numbers under one
    // word is a readout that has to be worked out rather than glanced at.
    check(
        "the disk sensor is not called Storage, which the panel already uses",
        groupedSensors.contains { $0.name == "Drive" }
            && !groupedSensors.contains { $0.name == "Storage" }
    )

    // Reaching a browser needs Accessibility, and the app must not pretend to
    // have it.
    //
    // This used to assert that the permission was absent, on the reasoning that
    // these checks run from a bare executable. That is a fact about the machine
    // rather than about the app: it holds on a Mac whose terminal has never
    // been granted Accessibility, and fails on one where it has — including
    // GitHub's runners, which grant it to the process that starts the job. A
    // check that a contributor fails for having a window manager installed is
    // telling them about their Mac, not about this code.
    //
    // What is true everywhere is that both halves of the behaviour give the same
    // answer: what the settings window says about the permission, and whether a
    // key press is actually sent. Be clear about what this catches and what it
    // does not — a second plain call to the same system function would agree
    // with the first, so this does not stop the duplication coming back. It
    // fails when the two answers can differ: one of them caching what it was
    // told at launch while the other asks live, or either being pointed at a
    // different signal. That is the shape the bug would really take, because
    // the permission is revoked and granted while the app is running.
    check("the panel and the key press agree about the permission", MediaKeys.isTrusted == MediaControl.hasPermission)

    // Whether the app can be a login item is a question about the BUNDLE, not
    // about whether it is already registered. Asking the registration made the
    // switch disable itself for exactly the people trying to switch it on: a
    // never-registered app reports notFound, which the old test read as "this
    // Mac cannot do it", and nothing else ever registers it.
    //
    // These checks run from a bare executable with no bundle identifier, which
    // is the case that genuinely cannot register — so this asserts the honest
    // answer for the process actually asking.
    check("a bare binary cannot be a login item", LoginItem.isSupported == false)
    check("and does not claim to be enabled", LoginItem.isEnabled == false)
    check(
        "the bundle is what decides, and this has none",
        Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app"
    )

    // How often Now Playing is looked at. Polling harder while a track sits
    // paused fixed a slow switch and tripled the idle cost — measured, 1.2% to
    // 7.5% — which is the wrong trade for a readout. The fast rate is now spent
    // only when the speakers are busy while our own track is paused, which is
    // the one arrangement that means something else is playing.
    func snapshot(playing: Bool) -> NowPlaying {
        NowPlaying(
            title: "t", artist: nil, isPlaying: playing, artwork: nil,
            source: .spotify, elapsed: nil, duration: nil, fetchedAt: Date()
        )
    }
    // Which tracks earn a place on the notch — the strip beside it AND the
    // card inside the panel, both fed from this one decision.
    //
    // A web page can claim the system's now-playing session without anyone
    // pressing play — a social feed autoplaying under the scroll — and it
    // arrives paused, at position zero, with no artist and no artwork. The
    // rule that keeps a paused SONG on the notch (so its artwork and resume
    // button survive a pause) used to keep those too, parking a browser tab's
    // title on the notch for the rest of the day. The reading in the first
    // check below is the real one, taken from MediaRemote while a LinkedIn
    // feed held the session.
    //
    // The panel is included deliberately: a media card with a 0:00 progress
    // bar and a play button is a claim that there is something to play, and
    // offering that for a page nobody started is the same untruth somewhere
    // quieter.
    func track(
        _ title: String, playing: Bool, elapsed: Double? = nil,
        source: MediaSource = .other
    ) -> NowPlaying {
        NowPlaying(
            title: title, artist: nil, isPlaying: playing, artwork: nil,
            source: source, elapsed: elapsed, duration: nil, fetchedAt: Date()
        )
    }
    check(
        "a feed that grabbed the session without playing is not shown at all",
        MediaMonitor.earnsPlace(
            track("Feed | LinkedIn", playing: false, elapsed: 0), playedTitle: nil
        ) == false
    )
    check(
        "anything actually playing is shown",
        MediaMonitor.earnsPlace(track("a song", playing: true), playedTitle: nil)
    )
    check(
        "a song you paused keeps its place",
        MediaMonitor.earnsPlace(
            track("a song", playing: false), playedTitle: "a song"
        )
    )
    check(
        "a track already part-way through counts as played",
        MediaMonitor.earnsPlace(
            track("resumed", playing: false, elapsed: 42), playedTitle: nil
        )
    )
    check(
        "one track's standing never passes to the next",
        MediaMonitor.earnsPlace(
            track("Feed | LinkedIn", playing: false, elapsed: 0),
            playedTitle: "a song played earlier"
        ) == false
    )
    check(
        "nothing at all earns nothing",
        MediaMonitor.earnsPlace(nil, playedTitle: "a song") == false
    )
    check(
        "playing is what marks a track as played",
        MediaMonitor.hasBeenPlayed(track("x", playing: true))
    )
    check(
        "and so is arriving part-way through",
        MediaMonitor.hasBeenPlayed(track("x", playing: false, elapsed: 3))
    )
    check(
        "but announced-and-never-started is not played",
        MediaMonitor.hasBeenPlayed(track("x", playing: false, elapsed: 0)) == false
    )
    check(
        "nor is one with no position at all",
        MediaMonitor.hasBeenPlayed(track("x", playing: false)) == false
    )
    // The rule is asked of every player equally — a paused Spotify track that
    // was never played is held to exactly the same standard as the feed.
    check(
        "the rule names no app: an unplayed Spotify track is refused too",
        MediaMonitor.earnsPlace(
            track("never started", playing: false, elapsed: 0, source: .spotify),
            playedTitle: nil
        ) == false
    )
    // The same feed, once it is actually played. Both readings below are real,
    // taken from MediaRemote three seconds apart: ignored, then playing.
    check(
        "the same feed, once actually played, is shown",
        MediaMonitor.earnsPlace(
            track("Feed | LinkedIn", playing: true, elapsed: 25.47), playedTitle: nil
        )
    )
    // Withholding a track must not make the monitor stop looking at it.
    //
    // A withheld track is still a track sitting there able to start, so it is
    // paced like the paused track it is. Pacing it like an EMPTY screen —
    // which is what asking these questions of the withheld view did — gave it
    // the laziest rate there is, so a feed that was ignored and then played
    // took up to fifteen seconds to appear. That reads as never appearing.
    check(
        "a withheld track is still paced as a track, not as an empty screen",
        MediaMonitor.interval(
            for: track("Feed | LinkedIn", playing: false, elapsed: 0),
            audioElsewhere: false
        ) == 12
    )
    check(
        "and briskly while something else is audible",
        MediaMonitor.interval(
            for: track("Feed | LinkedIn", playing: false, elapsed: 0),
            audioElsewhere: true
        ) == 2
    )
    check(
        "a look that found a track is never a fruitless one",
        MediaMonitor.interval(
            for: track("Feed | LinkedIn", playing: false, elapsed: 0),
            audioElsewhere: true, fruitlessLooks: 99
        ) == 2
    )

    check(
        "nothing playing is looked at least often",
        MediaMonitor.interval(for: nil, audioElsewhere: false) == 15
    )
    check(
        "a playing track is looked at often",
        MediaMonitor.interval(for: snapshot(playing: true), audioElsewhere: false) == 2
    )
    check(
        "a paused track in silence is left alone",
        MediaMonitor.interval(for: snapshot(playing: false), audioElsewhere: false) == 12
    )
    check(
        "a paused track while something else plays is chased",
        MediaMonitor.interval(for: snapshot(playing: false), audioElsewhere: true) == 2
    )
    check(
        "audio elsewhere does not speed up an already playing track",
        MediaMonitor.interval(for: snapshot(playing: true), audioElsewhere: true) == 2
    )
    // An empty notch while the speakers are busy is the one state that is about
    // to be wrong: something is playing and has not been found yet. This used
    // to wait the full idle interval regardless, which is what made a video
    // take several seconds to appear. The CoreAudio signal cannot cover it —
    // a browser holds its audio session open between videos, so starting one
    // changes nothing for the signal to fire on.
    check(
        "a sound with nothing on the notch is chased at once",
        MediaMonitor.interval(for: nil, audioElsewhere: true) == 2
    )
    // But audio running does not prove there is a track to find. A call, a
    // game, an alert — chasing those forever would cost a subprocess every two
    // seconds for the length of a meeting.
    check(
        "chasing a silent-running sound gives up",
        MediaMonitor.interval(for: nil, audioElsewhere: true, fruitlessLooks: 6) == 15
    )
    check(
        "and it is still chased on the last look before that",
        MediaMonitor.interval(for: nil, audioElsewhere: true, fruitlessLooks: 5) == 2
    )
    check(
        "a fruitless count means nothing once the sound has stopped",
        MediaMonitor.interval(for: nil, audioElsewhere: false, fruitlessLooks: 99) == 15
    )
    check(
        "and nothing once a track has actually been found",
        MediaMonitor.interval(for: snapshot(playing: true), audioElsewhere: true, fruitlessLooks: 99) == 2
    )

    // Processor load is a DIFFERENCE between two tick readings, never a single
    // one. The counters run since boot, so one reading on its own describes the
    // average since the machine started rather than what it is doing now.
    let idleThenBusy = (CPUTicks(busy: 1_000, idle: 9_000), CPUTicks(busy: 1_500, idle: 9_500))
    check(
        "load is the busy share of what moved between two readings",
        idleThenBusy.0.load(to: idleThenBusy.1) == 0.5
    )
    check(
        "a machine doing nothing reads zero",
        CPUTicks(busy: 100, idle: 100).load(to: CPUTicks(busy: 100, idle: 200)) == 0
    )
    check(
        "a machine doing only work reads one",
        CPUTicks(busy: 100, idle: 100).load(to: CPUTicks(busy: 200, idle: 100)) == 1
    )
    check(
        "two identical readings say nothing rather than zero",
        CPUTicks(busy: 100, idle: 100).load(to: CPUTicks(busy: 100, idle: 100)) == nil
    )
    check(
        "counters that went backwards are refused, not wrapped into nonsense",
        CPUTicks(busy: 500, idle: 500).load(to: CPUTicks(busy: 100, idle: 100)) == nil
    )
    check("the real processor reads back", CPUReader.ticks() != nil)
    check(
        "and its counters only ever climb",
        {
            guard let a = CPUReader.ticks() else { return false }
            Thread.sleep(forTimeInterval: 0.05)
            guard let b = CPUReader.ticks() else { return false }
            return b.total >= a.total
        }()
    )

    // Storage: the sums behind "74% full, 64.5 GB free".
    let disk = DiskUsage(name: "Macintosh HD", totalBytes: 245_107_195_904, freeBytes: 91_530_000_000)
    check("used is what is not free", disk.usedBytes == 245_107_195_904 - 91_530_000_000)
    check("percent full is rounded to a whole number", disk.percentUsed == 63)
    check(
        "an empty disk is not full",
        DiskUsage(name: "x", totalBytes: 1_000, freeBytes: 1_000).percentUsed == 0
    )
    check(
        "a full disk reads 100",
        DiskUsage(name: "x", totalBytes: 1_000, freeBytes: 0).percentUsed == 100
    )
    check(
        "a volume reporting no size divides by nothing rather than crashing",
        DiskUsage(name: "x", totalBytes: 0, freeBytes: 0).percentUsed == 0
    )
    check(
        "a disk cannot report more free than it holds",
        DiskUsage(name: "x", totalBytes: 1_000, freeBytes: 9_999).freeBytes == 1_000
    )
    check(
        "a negative free figure is not believed",
        DiskUsage(name: "x", totalBytes: 1_000, freeBytes: -5).freeBytes == 0
    )
    check("the real startup disk reads back", StorageReader.read(volume: StorageReader.volumeURL) != nil)

    // The bar is drawn in parts, so the parts must come to exactly the disk.
    // Free is what the volume reports and taken is the rest, so the sum is
    // exact by construction rather than by luck.
    let split = DiskUsage(name: "x", totalBytes: 1_000, freeBytes: 300)
    check("the segments come to exactly the whole disk", {
        let sum = split.segments.reduce(0.0) { $0 + $1.fraction }
        return abs(sum - 1.0) < 0.000001
    }())
    check("what is in use is everything not free", split.usedBytes == 700)
    check(
        "a disk reporting no size has no segments to draw",
        DiskUsage(name: "x", totalBytes: 0, freeBytes: 0).segments.isEmpty
    )

    // ── The regression this section exists for ───────────────────────────────
    //
    // "% full" was driven by volumeAvailableCapacityForImportantUsage, which
    // answers "how much could be MADE free for something important" — it counts
    // room macOS believes it could win back. Measured on a 245 GB disk holding
    // 180 GB, that key returned 229.95 GB, so the panel called a 74%-full disk
    // "7% full, 228 GB free". Every fixture above still passed, because a
    // fixture cannot tell you which of two real keys you should have asked.
    //
    // So the rule is pinned against the machine itself: read both keys, and if
    // they disagree, require the readout to follow the plain one.
    let volumeKeys: Set<URLResourceKey> = [
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
    ]
    if let real = StorageReader.read(volume: StorageReader.volumeURL),
       let values = try? StorageReader.volumeURL.resourceValues(forKeys: volumeKeys),
       let plainFree = values.volumeAvailableCapacity,
       let importantFree = values.volumeAvailableCapacityForImportantUsage {

        check("the disk's free space is the figure df and diskutil agree on", real.freeBytes == Int64(plainFree))
        check(
            "the optimistic \"could be made free\" figure is not used as free space",
            importantFree == Int64(plainFree) || real.freeBytes != Int64(importantFree)
        )
        check("free space is never reported as more than the disk holds", real.freeBytes <= real.totalBytes)
        check("the real disk's segments come to the whole disk", {
            let sum = real.segments.reduce(0.0) { $0 + $1.fraction }
            return abs(sum - 1.0) < 0.000001
        }())
        check("no segment of the real disk is negative", real.segments.allSatisfy { $0.fraction >= 0 })

        // An independent API, so the readout is corroborated rather than merely
        // self-consistent: statfs is what `df` itself reports.
        var fs = statfs()
        if statfs("/", &fs) == 0 {
            let statfsFree = Int64(fs.f_bavail) * Int64(fs.f_bsize)
            let drift = abs(Double(real.freeBytes - statfsFree)) / Double(max(1, statfsFree))
            if drift >= 0.02 {
                print("       reported \(real.freeBytes) vs statfs \(statfsFree)")
            }
            check("the free figure agrees with what df measures independently", drift < 0.02)
        } else {
            check("the free figure agrees with what df measures independently", false)
        }
    } else {
        check("the disk's free space is the figure df and diskutil agree on", false)
        check("the optimistic \"could be made free\" figure is not used as free space", false)
        check("free space is never reported as more than the disk holds", false)
        check("the real disk's segments come to the whole disk", false)
        check("no segment of the real disk is negative", false)
        check("the free figure agrees with what df measures independently", false)
    }

    // Sizes are shown in the units macOS uses — powers of a thousand, so the
    // number matches the one Finder is showing on the same disk.
    check("bytes stay bytes", Formatters.bytes(512) == "512 B")
    check("thousands are kilobytes", Formatters.bytes(49_000) == "49 KB")
    check("millions are megabytes", Formatters.bytes(5_500_000) == "5.5 MB")
    check("billions are gigabytes", Formatters.bytes(91_530_000_000) == "91.53 GB")
    check("trillions are terabytes", Formatters.bytes(2_000_000_000_000) == "2 TB")
    check("a negative size is not shown as negative", Formatters.bytes(-5) == "0 B")

    // Downloads: browser part-files are recognized, finished files are not.
    check("part crdownload", DownloadsMonitor.isPartFileName("movie.mp4.crdownload"))
    check("part download", DownloadsMonitor.isPartFileName("photo.jpg.download"))
    check("part part", DownloadsMonitor.isPartFileName("archive.zip.part"))
    check("finished not part", !DownloadsMonitor.isPartFileName("movie.mp4"))
    check("finished pdf not part", !DownloadsMonitor.isPartFileName("report.pdf"))

    // AirPods: parse battery out of `system_profiler SPBluetoothDataType`, only
    // for the AirPods block, only while connected (levels present).
    let apConnected = [
        "    Bluetooth:",
        "        Connected:",
        "          Hash's AirPods:",
        "              Case Battery Level: 81%",
        "              Left Battery Level: 81%",
        "              Right Battery Level: 100%",
        "              Minor Type: Headphones",
        "          Hash's Speaker:",
        "              Battery Level: 55%",
    ].joined(separator: "\n")
    let ap = AirPodsReader.parse(apConnected)
    check("airpods parses left", ap.left == 81)
    check("airpods parses right", ap.right == 100)
    check("airpods parses case", ap.caseLevel == 81)
    check("airpods stops at next device", ap.single == nil)
    check("airpods glance is the lower earbud", ap.glance == 81)

    let apDisconnected = [
        "        Not Connected:",
        "          Hash's AirPods:",
        "              Address: 08:65:18:5F:AF:0C",
        "              Minor Type: Headphones",
    ].joined(separator: "\n")
    check("airpods empty when disconnected", AirPodsReader.parse(apDisconnected).isEmpty)

    let apSingle = [
        "          Someone's AirPods Max:",
        "              Battery Level: 90%",
        "              Minor Type: Headphones",
    ].joined(separator: "\n")
    let single = AirPodsReader.parse(apSingle)
    check("airpods single-battery level", single.single == 90 && single.glance == 90)

    // System volume via CoreAudio: readable in range, and a same-value write
    // round-trips (harmless — it sets the volume it already has).
    if let volume = SystemVolume.read() {
        check("volume read in range", (0...100).contains(volume))
        SystemVolume.set(volume)
        check("volume same-value write round-trips", SystemVolume.read() == volume)
    } else {
        print("  note volume unavailable on this output device (skipped)")
    }

    // Settings: defaults, updates, and persistence round-trip.
    let defaults = InMemoryDefaults()
    let store = checkStore(defaults: defaults)
    let stub = StubFeature(id: "x", placement: .leading)
    store.seed(features: [stub])
    check("settings seed enables", store.isEnabled("x"))
    check("settings seed placement", store.features["x"]?.placement == .leading)

    store.update("x") { $0.enabled = false; $0.styleID = "word" }
    check("settings update disables", store.isEnabled("x") == false)
    check("settings update style", store.style(for: "x") == "word")

    store.flush()
    let reloaded = checkStore(defaults: defaults)
    check("settings persist enabled", reloaded.isEnabled("x") == false)
    check("settings persist style", reloaded.style(for: "x") == "word")

    // The overlay window keeps ONE width for its whole life. A width that
    // changes has to move the left edge to stay centred, and that move is
    // instant while SwiftUI animates the content re-centring inside it — the two
    // do not cancel, and the island sweeps sideways. Measured on a real close
    // before this was fixed: the panel sat at 262 in a 524-wide window and 176
    // in a 352-wide one.
    let widthState = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
        notchRect: CGRect(x: 562, y: 804, width: 156, height: 28),
        hasNotch: true
    ))
    let notch = CGRect(x: 562, y: 804, width: 156, height: 28)
    let constant = NotchWindowController.constantWidth(for: notch, state: widthState)
    check("the window is wide enough for the resting notch", constant >= widthState.collapsedWidth)
    check("wide enough for the open panel", constant >= widthState.expandedWidth)
    check(
        "wide enough for the live strip's furthest reach",
        constant >= 2 * max(
            widthState.liveLeadingWidth + notch.width / 2,
            notch.width / 2 + widthState.liveTrailingWidth
        )
    )
    check("and it is a whole number of points", constant == constant.rounded())

    // The same must hold on every shape of display, including a notchless one
    // where the island is a small stand-in pill.
    var coversEveryState = true
    for width in [132.0, 156.0, 200.0, 240.0] {
        let rect = CGRect(x: 640 - width / 2, y: 804, width: width, height: 28)
        let s = NotchState(geometry: NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
            notchRect: rect,
            hasNotch: true
        ))
        let w = NotchWindowController.constantWidth(for: rect, state: s)
        let liveReach = 2 * max(s.liveLeadingWidth + width / 2, width / 2 + s.liveTrailingWidth)
        if w < s.collapsedWidth || w < s.expandedWidth || w < liveReach { coversEveryState = false }
    }
    check("one width covers every state on any notch size", coversEveryState)

    // The panel's own controls live in the band either side of the physical
    // notch. That band is only usable if it is genuinely wider than the notch —
    // and the panel's width is derived, not fixed, so this has to hold at every
    // notch size rather than at the one on the developer's Mac.
    //
    // What this really pins is that the buttons cannot be squeezed out by a
    // later change to how the panel is sized. They used to float over the first
    // row instead of being placed, which is exactly the bug that made reordering
    // the panel put them on top of a readout.
    var shouldersFit = true
    var shouldersExactlyFillThePanel = true
    var controlsClearTheNotch = true
    for width in [132.0, 156.0, 200.0, 240.0, 320.0] {
        let rect = CGRect(x: 640 - width / 2, y: 804, width: width, height: 32)
        let s = NotchState(geometry: NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
            notchRect: rect,
            hasNotch: true
        ))
        if s.shoulderWidth < NotchState.minimumShoulderWidth { shouldersFit = false }
        // Centred in its shoulder, a control must still clear the hardware on
        // one side and the panel's edge on the other — by the same amount,
        // which is what being centred means.
        if s.controlClearance <= 0 { controlsClearTheNotch = false }
        // Two shoulders plus the hardware must come to exactly the panel's
        // width, or the buttons drift off its edges as the notch changes size.
        if abs(s.shoulderWidth * 2 + s.notchWidth - s.expandedWidth) > 0.001 {
            shouldersExactlyFillThePanel = false
        }
    }
    check("a control fits beside the notch at every notch size", shouldersFit)
    check("a centred control clears the hardware at every notch size", controlsClearTheNotch)
    check("the two shoulders and the notch come to the panel's width", shouldersExactlyFillThePanel)

    // A notchless display gets a stand-in pill rather than a real notch, and the
    // controls have to survive that too — it is the narrowest island the app
    // ever draws.
    let notchlessState = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        notchRect: CGRect(
            x: 720 - NotchGeometry.notchlessWidth / 2,
            y: 874 - NotchGeometry.notchlessHeight,
            width: NotchGeometry.notchlessWidth,
            height: NotchGeometry.notchlessHeight
        ),
        hasNotch: false
    ))
    check(
        "a control still fits beside the stand-in pill on a screen with no notch",
        notchlessState.shoulderWidth >= NotchState.minimumShoulderWidth
    )
    check(
        "and it is still centred clear of it",
        notchlessState.controlClearance > 0
    )

    // A shape that grows out of the notch has to converge ON the notch. The
    // live strip is lopsided on purpose, so its own centre is the wrong point:
    // anchoring there would collapse it beside the hardware rather than into it.
    let stripState = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
        notchRect: CGRect(x: 562, y: 804, width: 156, height: 28),
        hasNotch: true
    ))
    let anchor = stripState.notchAnchorInLiveStrip
    // The notch's centre sits at leading + half the notch, within the whole
    // strip — here 56 + 78 of 382.
    let expectedAnchor = (56.0 + 78.0) / 382.0
    check("the strip anchors on the notch", abs(anchor - expectedAnchor) < 0.001)
    check("which is left of the strip's own centre", anchor < 0.5)
    check(
        "the anchor lands inside the notch",
        anchor * stripState.liveWidth > 56 && anchor * stripState.liveWidth < 56 + 156
    )
    check(
        "a drop starts exactly as wide as the notch",
        abs(stripState.notchWidth / stripState.expandedWidth - 156.0 / 300.0) < 0.001
    )

    // On a notched display the island hangs from the screen's top edge and
    // wears the notch exactly. On one without, it must NOT: painting black over
    // the menu bar reads as a fault, so it hangs below it instead.
    let notched = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32),
        hasNotch: true
    )
    check("a notched display hangs from the screen edge", notched.islandTop == 982)

    // A display with no notch is given a shape rather than matched to one, and
    // it has to meet the top bezel exactly as the hardware does. It used to hang
    // BELOW the menu bar, which left a strip of desktop above it — a dark pill
    // attached to nothing, which reads as a fault rather than as restraint. Worse,
    // no adjustment could close that gap, because height only ever grew downwards.
    //
    // Built through the real rule rather than by hand: the checks that replaced
    // asserted things about a geometry the check itself had constructed, so they
    // would have passed whatever the code did.
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let notchless = NotchGeometry.notchless(screenFrame: screen, menuBarHeight: 25)
    check("a notchless island hangs from the screen edge, like the hardware", notchless.islandTop == 1080)
    check("and it reaches that edge with no gap above it", notchless.notchRect.maxY == 1080)
    check("it is exactly as tall as the menu bar", notchless.notchRect.height == 25)
    check("and centred on the screen", notchless.notchRect.midX == screen.midX)
    check("it still reports itself as having no notch", notchless.hasNotch == false)
    // A screen reporting something absurd must not produce a black slab across
    // the top or an invisible sliver.
    check(
        "an implausibly tall menu bar is bounded",
        NotchGeometry.notchless(screenFrame: screen, menuBarHeight: 400).notchRect.height
            == NotchGeometry.notchlessMaxHeight
    )
    check(
        "and an implausibly short one is too",
        NotchGeometry.notchless(screenFrame: screen, menuBarHeight: 1).notchRect.height
            == NotchGeometry.notchlessMinHeight
    )
    // The panel still opens below the menu bar, so nothing that drops down can
    // cover a menu — only the resting shape occupies that band.
    check(
        "the height adjustment can make the shape genuinely taller",
        IslandAdjustment.heightRange.upperBound >= 80
    )

    // Hand corrections: applied on top of the measurement, clamped so a
    // hand-edited file cannot push the island somewhere unreachable.
    var nudge = IslandAdjustment()
    check("no correction means automatic", nudge.isAutomatic)
    check("automatic changes nothing", nudge.applied(to: notched).notchRect == notched.notchRect)

    nudge.horizontal = 40
    check("a sideways nudge moves it", nudge.applied(to: notched).notchRect.midX == notched.notchRect.midX + 40)
    check("a sideways nudge does not resize it", nudge.applied(to: notched).notchRect.width == 200)

    nudge = IslandAdjustment()
    nudge.vertical = 30
    let lowered = nudge.applied(to: notched)
    check("a downward nudge lowers the island", lowered.islandTop == notched.islandTop - 30)
    check("a downward nudge lowers its rect too", lowered.notchRect.maxY == notched.notchRect.maxY - 30)

    nudge = IslandAdjustment()
    nudge.width = 60
    let widened = nudge.applied(to: notched)
    check("widening grows the island", widened.notchRect.width == 260)
    check("widening keeps it centred", widened.notchRect.midX == notched.notchRect.midX)

    var extreme = IslandAdjustment()
    extreme.horizontal = 9_999
    extreme.vertical = -9_999
    extreme.width = 9_999
    extreme.height = 9_999
    let safe = extreme.clamped
    check("a wild sideways value is clamped", safe.horizontal == IslandAdjustment.horizontalRange.upperBound)
    check("a wild upward value is clamped", safe.vertical == IslandAdjustment.verticalRange.lowerBound)
    check("a wild width is clamped", safe.width == IslandAdjustment.widthRange.upperBound)
    check("a wild height is clamped", safe.height == IslandAdjustment.heightRange.upperBound)
    check("clamping happens before it is applied", extreme.applied(to: notched).notchRect.width <= 200 + IslandAdjustment.widthRange.upperBound)

    // Corrections are per display, so one screen's fix never follows onto
    // another, and resetting removes the entry rather than storing zeroes.
    let posDefaults = InMemoryDefaults()
    let positioned = checkStore(defaults: posDefaults)
    var laptop = IslandAdjustment()
    laptop.horizontal = 12
    positioned.setAdjustment(laptop, for: "display-1")
    check("a correction is kept for its display", positioned.adjustment(for: "display-1").horizontal == 12)
    check("another display is untouched", positioned.adjustment(for: "display-2").isAutomatic)
    positioned.setAdjustment(IslandAdjustment(), for: "display-1")
    check("resetting clears the entry", positioned.adjustments["display-1"] == nil)

    positioned.setAdjustment(laptop, for: "display-1")
    positioned.flush()
    let reloadedPositions = checkStore(defaults: posDefaults)
    check("corrections survive a restart", reloadedPositions.adjustment(for: "display-1").horizontal == 12)

    // Dragging a Position slider must move the island under your hand. That
    // means the overlay reshapes in place on every value, rather than being
    // rebuilt behind a debounce — which only ever landed once you let go.
    if NotchGeometry.preferredScreen() != nil {
        let liveDefaults = InMemoryDefaults()
        let liveSettings = checkStore(defaults: liveDefaults)
        let liveContext = FeatureContext(settings: liveSettings)
        let liveController = NotchWindowController(registry: FeatureRegistry(), context: liveContext)

        let before = liveController.currentWindowFrame
        let key = NotchGeometry.preferredScreen().map { NotchGeometry.displayKey(for: $0) } ?? ""
        var slide = IslandAdjustment()
        slide.horizontal = 50
        liveSettings.setAdjustment(slide, for: key)
        let after = liveController.currentWindowFrame
        check("a correction moves the island immediately", after.midX == before.midX + 50)

        // Only the notch opens the panel. The live strip reaches far past it —
        // its trailing side alone is 170 points — and the menu bar's own status
        // items sit in exactly that space, so treating the strip as a trigger
        // meant reaching for the camera or Wi-Fi icon opened the panel over the
        // thing being reached for.
        let zone = liveController.openZone
        let notch = liveController.currentNotchRect
        check(
            "the opening zone is the notch, not the strip",
            zone.width <= notch.width + 16
        )
        check(
            "a status item to the right of the strip cannot open the panel",
            zone.contains(CGPoint(x: notch.midX + 170, y: notch.midY)) == false
        )
        check(
            "nor one to the left of it",
            zone.contains(CGPoint(x: notch.midX - 170, y: notch.midY)) == false
        )
        check(
            "the notch itself still opens it",
            zone.contains(CGPoint(x: notch.midX, y: notch.maxY - 2))
        )
        // The invariant that stops it flapping: anything that can open the
        // panel must also be able to keep it open.
        check(
            "whatever opens it can keep it open",
            liveController.keepOpenZone.contains(zone.origin)
                && liveController.keepOpenZone.union(zone) == liveController.keepOpenZone
        )

        // The keep-open zone has to reach the bottom of the panel as it really
        // is, not as the nominal height says. The panel grows with whatever is
        // switched on; a zone fixed at 460 covered the top two thirds of a tall
        // one, so the cursor left it before reaching the last row and the panel
        // shut on the way there. The timer is ordered last, so the timer was
        // the row nobody could reach.
        let tallPanel: CGFloat = 640
        let tallZone = NotchWindowController.expandedZone(
            notchRect: notch, islandTop: notch.maxY, width: 300, height: tallPanel
        )
        check(
            "the keep-open zone reaches the bottom of a tall panel",
            tallZone.contains(CGPoint(x: notch.midX, y: notch.maxY - tallPanel + 2))
        )
        check(
            "and a little past it, for a cursor arriving slowly",
            tallZone.contains(CGPoint(x: notch.midX, y: notch.maxY - tallPanel - 6))
        )
        check(
            "a taller panel gets a taller zone",
            NotchWindowController.expandedZone(
                notchRect: notch, islandTop: notch.maxY, width: 300, height: 640
            ).height > NotchWindowController.expandedZone(
                notchRect: notch, islandTop: notch.maxY, width: 300, height: 460
            ).height
        )
        check(
            "the zone still hangs from the island's top edge",
            tallZone.maxY == notch.maxY
        )

        // The alignment invariant, swept across every height a panel could
        // plausibly reach. The window frame and the keep-open zone are two
        // consumers of one measurement, and this bug has now appeared twice
        // from them working it out separately — so rather than fixing the
        // second instance and hoping, the agreement itself is what is checked.
        let screen = NotchGeometry.preferredScreen()?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = notch.maxY
        var aligned = true
        var capped = true
        var reaches = true
        for measured in stride(from: CGFloat(200), through: 2000, by: 37) {
            let height = NotchWindowController.expandedContentHeight(
                measured: measured, islandTop: top, screenFrame: screen
            )
            // Never taller than the room below the island.
            if height > top - screen.minY - NotchWindowController.panelBottomMargin + 0.5 {
                capped = false
            }
            // Never taller than the content asked for.
            if height > measured + 0.5 { aligned = false }
            // The zone must reach the bottom of whatever height was settled on.
            let zone = NotchWindowController.expandedZone(
                notchRect: notch, islandTop: top, width: 300, height: height
            )
            if !zone.contains(CGPoint(x: notch.midX, y: top - height + 1)) { reaches = false }
        }
        check("the panel never exceeds the room below the island", capped)
        check("nor claims more height than its content asked for", aligned)
        check("the keep-open zone reaches the bottom at every height", reaches)
        check(
            "an absurd panel is capped rather than run off the screen",
            NotchWindowController.expandedContentHeight(
                measured: 5000, islandTop: top, screenFrame: screen
            ) == top - screen.minY - NotchWindowController.panelBottomMargin
        )
        check(
            "the room below the island is what limits it, not the screen's height",
            NotchWindowController.expandedContentHeight(
                measured: 5000, islandTop: top, screenFrame: screen
            ) > screen.height * 0.8
        )

        // Before the panel has ever been measured, the window reserves the
        // whole column rather than guessing at a height. Asking for everything
        // has to come back as the room that exists, or the first open of a
        // launch would put the window off the bottom of the screen instead of
        // merely being generous.
        //
        // Too much window costs nothing — it is transparent and click-through.
        // Too little clips the panel mid-drop and makes the window step down
        // underneath it, which is measurable: before this, one opening set the
        // window three times, at 84 points, then 592, then 632.
        check(
            "asking for every point there is comes back as the room there is",
            NotchWindowController.expandedContentHeight(
                measured: .greatestFiniteMagnitude, islandTop: top, screenFrame: screen
            ) == top - screen.minY - NotchWindowController.panelBottomMargin
        )
        check(
            "and it is still a finite height",
            NotchWindowController.expandedContentHeight(
                measured: .greatestFiniteMagnitude, islandTop: top, screenFrame: screen
            ).isFinite
        )

        // Settings hangs off the panel's right edge, sharing its top edge so
        // the two read as one surface rather than as a window that happened to
        // appear nearby.
        let panel = CGRect(x: 490, y: 315, width: 300, height: 517)
        let roomy = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let beside = SettingsWindowController.frame(besideAnchor: panel, in: roomy)
        check("settings hangs from the panel's top edge", beside.maxY == panel.maxY)
        check("settings sits to the right of the panel", beside.minX > panel.maxX)
        check("with a gap, not touching", beside.minX - panel.maxX >= 8)

        // A laptop display has far less room to the right than a desk monitor,
        // and running off the screen is worse than overlapping the island.
        let tight = CGRect(x: 0, y: 0, width: 1280, height: 832)
        let clamped = SettingsWindowController.frame(
            besideAnchor: CGRect(x: 490, y: 315, width: 300, height: 517), in: tight
        )
        check("it never runs off the right edge", clamped.maxX <= tight.maxX)
        check("nor off the left", clamped.minX >= tight.minX)

        // Hung from the top of a panel on a short screen, it shortens rather
        // than hanging past the bottom of the display.
        let short = CGRect(x: 0, y: 0, width: 1280, height: 700)
        let shortened = SettingsWindowController.frame(
            besideAnchor: CGRect(x: 490, y: 200, width: 300, height: 500), in: short
        )
        check("it never hangs below the screen", shortened.minY >= short.minY)

        slide.horizontal = 80
        liveSettings.setAdjustment(slide, for: key)
        check(
            "each further value moves it again",
            liveController.currentWindowFrame.midX == before.midX + 80
        )

        liveSettings.setAdjustment(IslandAdjustment(), for: key)
        check("clearing it returns the island", liveController.currentWindowFrame.midX == before.midX)

        var taller = IslandAdjustment()
        taller.height = 20
        liveSettings.setAdjustment(taller, for: key)
        check(
            "a size correction resizes it immediately",
            liveController.currentWindowFrame.height > before.height
        )
        liveSettings.setAdjustment(IslandAdjustment(), for: key)
    } else {
        print("  note no screen attached, live-adjustment checks skipped")
    }

    // Reordering: dragging one indicator onto another moves it there, and a
    // drag that makes no sense leaves the order alone rather than corrupting it.
    let order = ["media", "tokens", "network", "battery"]
    check(
        "dragging down moves the row",
        SettingsReorder.moving("media", before: "network", in: order)
            == ["tokens", "network", "media", "battery"]
    )
    check(
        "dragging up moves the row",
        SettingsReorder.moving("battery", before: "tokens", in: order)
            == ["media", "battery", "tokens", "network"]
    )
    check(
        "dropping on itself changes nothing",
        SettingsReorder.moving("media", before: "media", in: order) == order
    )
    check(
        "an unknown row changes nothing",
        SettingsReorder.moving("ghost", before: "media", in: order) == order
    )
    check(
        "reordering never loses or duplicates a row",
        Set(SettingsReorder.moving("media", before: "battery", in: order)) == Set(order)
            && SettingsReorder.moving("media", before: "battery", in: order).count == order.count
    )

    // Battery saver is one number in one place, and it is the number every
    // sampler multiplies by.
    let scaleDefaults = InMemoryDefaults()
    let scaled = checkStore(defaults: scaleDefaults)
    check("normally everything samples at its own rate", scaled.samplingScale == 1)
    scaled.batterySaver = true
    check("battery saver halves how often things sample", scaled.samplingScale == 2)

    // An accent id that no longer exists must still leave the island tinted.
    check("a known accent resolves", AccentColor.named("green").name == "Green")
    check("an unknown accent falls back", AccentColor.named("chartreuse").id == AccentColor.default.id)
    check("the default accent is in the list", AccentColor.all.contains { $0.id == AccentColor.default.id })

    // Appearance and alert choices survive a restart.
    scaled.appearance.accentID = "purple"
    scaled.appearance.panelFill = .solid
    scaled.appearance.motion = .calm
    scaled.alerts.noticeSeconds = 7
    scaled.flush()
    let reopened = checkStore(defaults: scaleDefaults)
    check("the accent is remembered", reopened.appearance.accentID == "purple")
    check("the panel fill is remembered", reopened.appearance.panelFill == .solid)
    check("the motion is remembered", reopened.appearance.motion == .calm)
    check("the alert length is remembered", reopened.alerts.noticeSeconds == 7)
    check("battery saver is remembered", reopened.batterySaver)
    check("calm motion is slower than lively",
          AppearanceSettings.Motion.calm.responseScale > AppearanceSettings.Motion.lively.responseScale)

    // The reader's chosen alert length overrides whatever the poster suggested.
    let posted = LiveActivity(
        id: "p", icon: "checkmark", title: "Done", subtitle: nil,
        progress: nil, endsAt: nil, dismissAfter: 3
    )
    let start = Date()
    check(
        "the poster's length is used when there is no preference",
        posted.dismissalDate(firstSeen: start) == start.addingTimeInterval(3)
    )
    check(
        "your preference wins over the poster's",
        posted.dismissalDate(firstSeen: start, preferring: 8) == start.addingTimeInterval(8)
    )
    let countdown = LiveActivity(
        id: "c", icon: "bicycle", title: "Delivery", subtitle: nil,
        progress: nil, endsAt: Date().addingTimeInterval(600), dismissAfter: nil
    )
    check(
        "a countdown is never cut short by the notice preference",
        countdown.dismissalDate(firstSeen: start, preferring: 8) == nil
    )

    // Renaming the app changes the preferences domain, so settings saved under
    // the old name must be carried over exactly once and rewritten under the new
    // key — otherwise an existing install silently comes back reset.
    //
    // There are now TWO old names to carry over from, because the app has come
    // back around to a name it already had: "hashnotch" (first), "hashdisland"
    // (second), "hashnotch" again (now, under a new key). A machine that has
    // been through all three has a document under both old keys, and only the
    // hashdisland one is what its owner last chose.
    let legacyDefaults = InMemoryDefaults()
    let freshDefaults = InMemoryDefaults()
    let legacyDocument = """
    {"features":{"x":{"enabled":false,"placement":"trailing","styleID":"word","order":4}},"launchAtLogin":true}
    """
    legacyDefaults.set(Data(legacyDocument.utf8), forKey: "hashdisland.settings.v2")

    let migrated = SettingsStore(defaults: freshDefaults, legacyDefaults: legacyDefaults)
    check("settings carry over from the old name", migrated.isEnabled("x") == false)
    check("settings carry over the style", migrated.style(for: "x") == "word")
    check("settings carry over launch at login", migrated.launchAtLogin)
    check("carried-over settings are not a first run", migrated.isFirstRun == false)
    // An install that predates the consent screen has already chosen its
    // indicators, and an update must not stop it dead to ask a question it has
    // effectively answered. The legacy document above has no such field — the
    // exact shape written before this existed — and reads as having agreed.
    check("an existing install is not asked again", migrated.hasAcceptedReading)
    migrated.flush()
    check(
        "carried-over settings are rewritten under the new key",
        freshDefaults.data(forKey: "hashnotch.settings.v3") != nil
    )
    check(
        "the new key is not the key the first name used",
        freshDefaults.data(forKey: "hashnotch.settings.v2") == nil
    )

    // The name this app started with is still carried over, for somebody who
    // never ran the name in between.
    let firstNameDefaults = InMemoryDefaults()
    firstNameDefaults.set(Data(legacyDocument.utf8), forKey: "hashnotch.settings.v2")
    check(
        "settings carry over from the name before last",
        SettingsStore(
            defaults: InMemoryDefaults(),
            legacyDefaults: firstNameDefaults
        ).style(for: "x") == "word"
    )

    // Both old names present at once: the more recent one wins. Getting this
    // backwards would hand somebody the choices they made two renames ago and
    // look exactly like settings being lost.
    let bothDefaults = InMemoryDefaults()
    let staleDocument = """
    {"features":{"x":{"enabled":false,"placement":"leading","styleID":"stale","order":4}},"launchAtLogin":false}
    """
    bothDefaults.set(Data(staleDocument.utf8), forKey: "hashnotch.settings.v2")
    bothDefaults.set(Data(legacyDocument.utf8), forKey: "hashdisland.settings.v2")
    check(
        "with both old names on disk the newer one is used",
        SettingsStore(
            defaults: InMemoryDefaults(),
            legacyDefaults: bothDefaults
        ).style(for: "x") == "word"
    )

    // Once rewritten, the old copy is never needed again.
    legacyDefaults.removeObject(forKey: "hashdisland.settings.v2")
    let afterMigration = SettingsStore(defaults: freshDefaults, legacyDefaults: legacyDefaults)
    check("settings survive without the old copy", afterMigration.style(for: "x") == "word")

    // A genuinely new install still counts as a first run.
    check(
        "a clean install is still a first run",
        SettingsStore(
            defaults: InMemoryDefaults(),
            legacyDefaults: InMemoryDefaults()
        ).isFirstRun
    )

}

// ── Only one island layer at a time ──────────────────────────────────────────
//
// "Three states, and it is only ever in one of them" is the app's central
// promise about how it looks, and it was broken: an activity arriving while the
// panel opened left the strip on screen beside it. Because the strip is WIDER
// than the panel it did not even hide behind it — the artwork stuck out one
// side and the title the other — and it stayed for as long as the panel was
// held open by the settings window.
//
// Reproduced by driving the panel open and shut while posting activities, which
// caught the two flags disagreeing eight times in forty seconds. That is why
// this is checked rather than reasoned about: the window is a fraction of a
// second wide, and nobody can stage it by hand.
do {
    check(
        "the strip shows when it is wanted and the panel is shut",
        IslandLayers.stripIsVisible(liveShown: true, panelExpanded: false)
    )
    check(
        "an open panel hides the strip, whatever the strip thinks",
        !IslandLayers.stripIsVisible(liveShown: true, panelExpanded: true)
    )
    check(
        "nothing is shown when there is nothing live",
        !IslandLayers.stripIsVisible(liveShown: false, panelExpanded: false)
    )
    // The promise stated directly: no combination of the two flags puts the
    // strip and the panel on screen together.
    var bothEverShown = false
    for liveShown in [true, false] {
        for panelExpanded in [true, false] {
            if IslandLayers.showsBothStripAndPanel(
                liveShown: liveShown, panelExpanded: panelExpanded
            ) {
                bothEverShown = true
            }
        }
    }
    check("the strip and the panel are never on screen together", !bothEverShown)
}

// ── A Mac is not always a MacBook ────────────────────────────────────────────
//
// An iMac, a Mac mini, a Mac Studio and a Mac Pro have no battery, and every
// part of that indicator is meaningless on one: no level, no time remaining, no
// time to full, no adapter. It drew anyway, dimmed, which reads as broken
// rather than as not applicable.
//
// The trap is the obvious version of the fix. `hasBattery` starts false and
// only becomes true once a reading lands, so hiding on "not hasBattery" would
// hide the indicator on EVERY Mac for the instant before the first reading —
// and then pop it in. So the question is asked of two facts, not one: a reading
// has been taken, AND it found nothing.
MainActor.assumeIsolated {
    check(
        "a Mac that has been read and has no battery hides the indicator",
        BatteryMonitor.isUnavailable(hasSampled: true, hasBattery: false)
    )
    check(
        "a Mac not yet read keeps it, whatever hasBattery happens to say",
        !BatteryMonitor.isUnavailable(hasSampled: false, hasBattery: false)
    )
    check(
        "a laptop keeps its battery indicator",
        !BatteryMonitor.isUnavailable(hasSampled: true, hasBattery: true)
    )
}

// ── The bezel is still the notch ─────────────────────────────────────────────
//
// Hovering the notch opened the panel, and then pushing the cursor up against
// the bezel — still squarely over the notch — shut it again.
//
// The cause is one word of geometry: `CGRect.contains` EXCLUDES its own maxY,
// and both hover zones ended exactly at the island's top edge. On a Mac with a
// notch that edge is the screen's top edge, which is precisely where the cursor
// lands when it is pushed as far up as it goes. So the topmost row of points
// over the notch counted as outside the notch.
//
// Reaching past the screen's top edge is free — there is no screen up there to
// be in — but only where the island is already AT that edge. On a display with
// no notch the island hangs below the menu bar, and a zone growing upward there
// would sit under the menu bar's own status items and open the panel over the
// icon being reached for.
MainActor.assumeIsolated {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let notch = CGRect(x: 642, y: 872, width: 156, height: 28)

    check(
        "an island at the screen's edge reaches past it",
        NotchWindowController.topOvershoot(islandTop: screen.maxY, screenFrame: screen) > 0
    )
    check(
        "a measured edge a hair short still counts as the screen's edge",
        NotchWindowController.topOvershoot(islandTop: screen.maxY - 0.4, screenFrame: screen) > 0
    )
    // The notchless case: the island hangs below a 24pt menu bar, and the strip
    // of screen above it belongs to the menu bar's status items.
    check(
        "an island below a menu bar never reaches up into it",
        NotchWindowController.topOvershoot(islandTop: screen.maxY - 24, screenFrame: screen) == 0
    )

    // The failure itself, stated as the user meets it: the very top row of
    // points over the notch has to be inside the zone that keeps the panel open.
    let overshoot = NotchWindowController.topOvershoot(islandTop: screen.maxY, screenFrame: screen)
    let opened = NotchWindowController.expandedZone(
        notchRect: notch, islandTop: screen.maxY, width: 320, height: 300,
        topOvershoot: overshoot
    )
    let atTheBezel = CGPoint(x: notch.midX, y: screen.maxY)
    check("the screen's top edge, over the notch, is inside the panel zone", opened.contains(atTheBezel))
    check(
        "without the overshoot that same point falls outside",
        !NotchWindowController.expandedZone(
            notchRect: notch, islandTop: screen.maxY, width: 320, height: 300
        ).contains(atTheBezel)
    )

    // And the zone still hangs from the island, so nothing below it moved.
    check(
        "reaching up does not move the zone's bottom edge",
        opened.minY == NotchWindowController.expandedZone(
            notchRect: notch, islandTop: screen.maxY, width: 320, height: 300
        ).minY
    )
}

// ── Putting things back ──────────────────────────────────────────────────────
//
// A reset is the one control that can destroy work, so what it does and what it
// leaves alone both have to be exact. Two of these matter more than the rest:
//
// The feature list must come back COMPLETE. `seed` only fills in ids it has
// never seen and it runs once at launch, so a reset that merely emptied the
// dictionary would leave the settings window bound to nothing until the next
// start — every indicator reading as absent rather than as its default.
//
// And consent must SURVIVE. `isFirstRun` is fixed when the store is built, so
// the opening window cannot be shown again without a relaunch, while
// `syncRunning` refuses to start anything at all until consent is given. A
// reset that cleared it would stop every indicator with no way on screen to say
// yes again — a settings button that bricks the app until it is restarted.
MainActor.assumeIsolated {
    let resetDefaults = InMemoryDefaults()
    let settings = checkStore(defaults: resetDefaults)
    let descriptors = [
        FeatureDescriptor(id: "alpha", title: "Alpha", options: []),
        FeatureDescriptor(id: "beta", title: "Beta", options: []),
    ]
    let registry = FeatureRegistry()
    registry.register([
        StubFeature(id: "alpha", placement: .expanded),
        StubFeature(id: "beta", placement: .leading),
    ])
    settings.seed(features: registry.features)

    // Move everything away from its default, on every page.
    settings.appearance.accentID = "nothing-like-the-default"
    settings.appearance.motion = .lively
    settings.appearance.panelFill = .glass
    settings.appearance.panelCornerRadius = 4
    settings.alerts.noticeSeconds = 99
    settings.batterySaver = true
    settings.canSwitchLowPowerMode = true
    settings.canPressMediaKeys = true
    settings.tokenScanInterval = .never
    settings.networkShowsApps = false
    settings.networkAppsExpanded = false
    var nudged = IslandAdjustment()
    nudged.horizontal = 9
    settings.setAdjustment(nudged, for: "display-1")
    settings.update("alpha") { $0.enabled = false }
    settings.setOrder(["beta", "alpha"])

    // Appearance alone: the look goes back, everything else is untouched.
    settings.resetAppearance()
    check("resetting appearance restores the accent", settings.appearance.accentID == AccentColor.default.id)
    check("resetting appearance restores the motion", settings.appearance.motion == .standard)
    check("resetting appearance restores the fill", settings.appearance.panelFill == .solid)
    check(
        "resetting appearance restores the rounding",
        settings.appearance.panelCornerRadius == AppearanceSettings().panelCornerRadius
    )
    check("resetting appearance leaves the alerts alone", settings.alerts.noticeSeconds == 99)
    check("resetting appearance leaves battery saver alone", settings.batterySaver)
    check("resetting appearance leaves the position alone", settings.adjustments["display-1"] != nil)
    check("resetting appearance leaves an indicator switched off", !settings.isEnabled("alpha"))

    // Everything: every page goes back.
    settings.appearance.motion = .calm
    settings.resetAll(features: descriptors)
    check("resetting everything restores the look", settings.appearance.motion == .standard)
    check("resetting everything restores the alerts", settings.alerts.noticeSeconds == AlertSettings().noticeSeconds)
    check("resetting everything clears battery saver", !settings.batterySaver)
    check("resetting everything clears the low-power opt-in", !settings.canSwitchLowPowerMode)
    check("resetting everything clears the media-key opt-in", !settings.canPressMediaKeys)
    check(
        "resetting everything restores how often tokens are counted",
        settings.tokenScanInterval == SettingsStore.defaultTokenScanInterval
    )
    check(
        "resetting everything restores naming the programs that used the most",
        settings.networkShowsApps == SettingsStore.defaultNetworkShowsApps
    )
    check(
        "resetting everything reopens the by-app list",
        settings.networkAppsExpanded == SettingsStore.defaultNetworkAppsExpanded
    )
    check("resetting everything forgets every position correction", settings.adjustments.isEmpty)

    // A choice about what the app is allowed to read has to survive a quit, and
    // a settings file written before the choice existed has to take the default
    // rather than decoding as false — an update that silently switches
    // something OFF is as much a surprise as one that switches it on.
    let appsDefaults = InMemoryDefaults()
    let beforeQuit = checkStore(defaults: appsDefaults)
    beforeQuit.networkShowsApps = false
    beforeQuit.flush()
    let afterQuit = checkStore(defaults: appsDefaults)
    check("saying no to naming programs survives a quit", afterQuit.networkShowsApps == false)
    afterQuit.networkShowsApps = true
    afterQuit.flush()
    check("and so does saying yes", checkStore(defaults: appsDefaults).networkShowsApps)

    // Shutting the list is remembered too. A disclosure that springs open again
    // on every glance is one the app is re-deciding rather than the person.
    let shutList = checkStore(defaults: appsDefaults)
    shutList.networkAppsExpanded = false
    shutList.flush()
    check("a shut by-app list stays shut",
          checkStore(defaults: appsDefaults).networkAppsExpanded == false)

    // A settings file written before this existed. It must take the default
    // rather than decoding as false: an update that silently switches
    // something OFF is as much of a surprise as one that switches it on, and
    // this field's absence means "no opinion", not "no".
    let olderDefaults = InMemoryDefaults()
    olderDefaults.set(
        Data(#"{"features":{},"launchAtLogin":false,"hasAcceptedReading":true}"#.utf8),
        forKey: "hashnotch.settings.v3"
    )
    let olderStore = SettingsStore(defaults: olderDefaults, legacyDefaults: InMemoryDefaults())
    check(
        "a settings file from before this existed takes the default",
        olderStore.networkShowsApps == SettingsStore.defaultNetworkShowsApps
    )
    check(
        "and finds the by-app list open rather than shut",
        olderStore.networkAppsExpanded == SettingsStore.defaultNetworkAppsExpanded
    )

    // The two that would be silent failures.
    check(
        "resetting everything leaves an entry for every indicator",
        Set(settings.features.keys) == Set(descriptors.map(\.id))
    )
    check("resetting everything switches every indicator back on", settings.isEnabled("alpha"))
    check(
        "resetting everything restores the registration order",
        descriptors.enumerated().allSatisfy { settings.features[$0.element.id]?.order == $0.offset }
    )
    check("resetting everything keeps consent given", settings.hasAcceptedReading)
    check(
        "resetting everything keeps each feature's own placement",
        settings.features["beta"]?.placement == .leading
    )

}

// ── Leave nothing behind ─────────────────────────────────────────────────────
//
// Several checks need a settings store of their own, so they make one in a
// throwaway preference domain named with a fresh UUID. Most tidied up after
// themselves; three did not, and since the name is unique per RUN, every run
// left more behind. On the machine this was found on there were **1201** of
// them — real files under ~/Library/Preferences, put there by a project whose
// README promises `defaults delete com.hashnotch.app` is the whole cleanup.
//
// Cleaning each one where it is created was the obvious fix and the wrong one:
// it is exactly the step the next person to add a suite will forget. Sweeping
// them all at the end was the second wrong one, and it took longer to see —
// see `InMemoryDefaults`, which is where this ends up. No cleanup written in
// this process outlives it, so the checks stopped making preference domains
// instead. What is left below only clears up after older builds that did.

/// The throwaway domains still on disk. `CFPreferencesCopyApplicationList` is
/// unavailable to Swift, so this reads where the domains actually live — one
/// plist per domain, which is the same thing `defaults domains` enumerates.
/// A settings store for the checks, isolated from the machine running them.
///
/// `SettingsStore` falls back to the app's PREVIOUS preference domain when the
/// current one is empty — that is how an existing install keeps its choices
/// across the rename, and it must keep working. In a check it is a trapdoor: a
/// store built on a throwaway suite quietly loaded the DEVELOPER's real
/// settings from `com.hashnotch.app`, so a check could pass on the one machine
/// that happened to have them and fail on every other, CI included. Handing it
/// an empty legacy suite shuts that door; the suite carries the checks' prefix
/// so the sweep at the end removes it like any other.
///
/// `accepted` is explicit because a genuinely fresh store has NOT agreed to
/// anything, and the registry refuses to start features until it has. Most
/// checks are about something else and want a store that has; the ones about
/// the gate itself pass false.
@MainActor
func checkStore(defaults: UserDefaults, accepted: Bool = true) -> SettingsStore {
    let noLegacy = InMemoryDefaults()
    let store = SettingsStore(defaults: defaults, legacyDefaults: noLegacy)
    store.hasAcceptedReading = accepted
    return store
}

func strayCheckDomains() -> [String] {
    let preferences = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences")
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
    return entries
        .filter { $0.hasPrefix(checkDomainPrefix) && $0.hasSuffix(".plist") }
        .map { String($0.dropLast(".plist".count)) }
}

// Nothing here creates a preference domain any more, so there is nothing of
// this run's to clean up. See `InMemoryDefaults` for why: no amount of tidying
// from inside the process survives the exit, because `cfprefsd` writes an empty
// plist for any domain it has been shown, on its own schedule, afterwards. The
// only cleanup that works is not making one.
//
// What remains is clearing up after OLDER builds of these checks, which did
// make them and did leave them behind. That is worth doing once — somebody
// running this on a machine that has the litter should not have to find out
// about it separately — and it costs a directory listing.
let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Preferences")
let leftByOlderBuilds = strayCheckDomains()
for name in leftByOlderBuilds {
    UserDefaults.standard.removePersistentDomain(forName: name)
    try? FileManager.default.removeItem(
        at: preferencesDirectory.appendingPathComponent("\(name).plist")
    )
}
UserDefaults.standard.synchronize()

if !leftByOlderBuilds.isEmpty {
    print("       cleared \(leftByOlderBuilds.count) domain(s) left by an older build of these checks")
}

// The claim, and it is now a claim about this run rather than about a folder at
// one instant. The old version of this check asked whether the folder was clean
// and was answered honestly and uselessly: the files arrived after it, once
// this process was gone and nothing was watching.
check(
    "the checks create no preference domains at all",
    strayCheckDomains().isEmpty
)
// And the store the checks run against really is the one that cannot reach the
// preferences system — the claim above is only worth anything if that is true.
let doubleCheck = InMemoryDefaults()
doubleCheck.set(Data("x".utf8), forKey: "hashnotch.checks.canary")
check(
    "a throwaway store keeps what it is given",
    doubleCheck.data(forKey: "hashnotch.checks.canary") != nil
)
check(
    "and never writes it where the real preferences live",
    UserDefaults.standard.persistentDomain(forName: "hashnotch.checks.canary") == nil
        && !FileManager.default.fileExists(
            atPath: preferencesDirectory.appendingPathComponent("hashnotch.checks.canary.plist").path
        )
)

if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
