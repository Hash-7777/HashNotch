import Foundation

/// Holds the set of enabled features and hands them to the HUD.
///
/// The registry is the seam between "which features exist" (decided once, in the
/// app's FeatureManifest) and "how features are laid out and driven" (the core).
/// Nothing here knows any concrete feature type.
@MainActor
public final class FeatureRegistry {
    public private(set) var features: [NotchFeature] = []

    /// Which features are actually running. Tracked so a settings change can
    /// start or stop the one that changed without disturbing the others.
    private var running: Set<String> = []

    public init() {}

    /// The order a fresh install shows the indicators in.
    ///
    /// Lives here, in the core, rather than being implied by the order somebody
    /// happened to type the manifest in — the manifest sorts itself by this, so
    /// the two cannot drift and a feature added to the manifest cannot silently
    /// rearrange everybody's panel. Anything not named here goes to the end,
    /// which is what a newly added feature should do.
    ///
    /// The arrangement: what you are doing, then what the machine is doing,
    /// then what you asked it to do. Now playing and activities first because
    /// they change constantly and are why the panel gets opened; downloads next
    /// as the other thing that arrives on its own. Then the machine's vital
    /// signs — connection, battery, what is in your ears. Then the figures you
    /// read rather than watch: tokens, temperatures, memory, processor. Timer
    /// and disk last, because a timer is set and forgotten and a disk changes
    /// over weeks.
    ///
    /// Only a starting point — every one of them can be dragged anywhere.
    public static let defaultOrder: [String] = [
        "call", "media", "activities", "downloads",
        "network", "battery", "airpods",
        "tokens", "thermal", "memory", "cpu",
        "timer", "storage",
    ]

    /// `features` arranged into `defaultOrder`, with anything unlisted kept in
    /// the caller's order at the end.
    public static func inDefaultOrder(_ features: [NotchFeature]) -> [NotchFeature] {
        features.enumerated()
            .sorted { lhs, rhs in
                let l = defaultOrder.firstIndex(of: lhs.element.id) ?? defaultOrder.count + lhs.offset
                let r = defaultOrder.firstIndex(of: rhs.element.id) ?? defaultOrder.count + rhs.offset
                return l < r
            }
            .map(\.element)
    }

    public func register(_ feature: NotchFeature) {
        features.append(feature)
        orderedCache = nil
    }

    public func register(_ newFeatures: [NotchFeature]) {
        features.append(contentsOf: newFeatures)
        orderedCache = nil
    }

    /// Features assigned to a given placement, in registration order.
    public func features(for placement: FeaturePlacement) -> [NotchFeature] {
        features.filter { $0.placement == placement }
    }

    /// The enabled features, in the order they should be drawn.
    ///
    /// Cached against `SettingsStore.featuresGeneration`, because the island
    /// asks for this while it is drawing and the answer can only change when a
    /// setting does. The island's body re-evaluates on every published change
    /// from every monitor — a token total, a CPU sample, each frame of an
    /// opening spring — and each of those was previously paying for a map, a
    /// filter, a sort and eleven config lookups to arrive at the same list it
    /// had a moment earlier.
    ///
    /// Ties break on id. Two features can only share an `order` if a saved
    /// document predates `seed`, and `Array.sorted` is not a stable sort, so
    /// without this the pair could swap places between one redraw and the next.
    public func orderedEnabled(using settings: SettingsStore) -> [NotchFeature] {
        if let cache = orderedCache, cache.generation == settings.featuresGeneration {
            return cache.value
        }
        // Written as explicit steps rather than one chain: the fused
        // map/filter/sort/map defeated the type checker outright.
        var ranked: [(feature: NotchFeature, order: Int)] = []
        ranked.reserveCapacity(features.count)
        for (index, feature) in features.enumerated() {
            let config = settings.config(for: feature, index: index)
            guard config.enabled else { continue }
            ranked.append((feature, config.order))
        }
        ranked.sort { left, right in
            left.order == right.order
                ? left.feature.id < right.feature.id
                : left.order < right.order
        }
        let value = ranked.map(\.feature)
        orderedCache = (settings.featuresGeneration, value)
        return value
    }

    private var orderedCache: (generation: Int, value: [NotchFeature])?

    /// Bring what is running in line with what the user has switched on: start
    /// every enabled feature that is not running, stop every disabled one that
    /// is.
    ///
    /// A feature that is switched off is stopped, not merely hidden. Hiding it
    /// while its monitor carried on would mean turning Downloads off still
    /// listed the folder, turning AirPods off still asked the system about
    /// Bluetooth, and turning Now Playing off still asked Spotify, Music, and
    /// the browsers for what they were doing — permission prompts and all.
    /// Nobody means "keep doing it, just don't tell me" when they turn
    /// something off, and an app that reads what it has been asked to stop
    /// reading cannot claim to be verifiable by reading its source.
    ///
    /// Idempotent, so it is safe to call on every settings change: a feature
    /// already in the right state is left alone rather than restarted.
    /// Nothing runs until somebody has been told what running means.
    ///
    /// Every switch above was already honoured — a feature that is off opens no
    /// files and spawns no subprocess — but they all ship ON, and this ran at
    /// launch before the user had seen a single word about what any of them
    /// read. So the honest description of a first launch was: the app listed
    /// the Downloads folder, asked macOS which processes held the microphone,
    /// and started reading what was playing — and THEN offered the switches.
    ///
    /// Being able to switch something off afterwards is not the same as having
    /// been asked. Until the answer is yes this stops everything rather than
    /// starting anything, so the state before consent IS the everything-off
    /// state rather than a promise about it.
    public func syncRunning(context: FeatureContext) {
        guard context.settings.hasAcceptedReading else {
            stopAll()
            return
        }
        for feature in features {
            let wanted = context.settings.isEnabled(feature.id)
            if wanted, !running.contains(feature.id) {
                feature.start(context: context)
                running.insert(feature.id)
            } else if !wanted, running.contains(feature.id) {
                feature.stop()
                running.remove(feature.id)
            }
        }
    }

    public func stopAll() {
        features.forEach { $0.stop() }
        running.removeAll()
    }

    /// Offer a sideways swipe over the open panel to the features, in
    /// registration order, until one takes it. Returns whether any did.
    ///
    /// Only RUNNING features are asked. A feature the user has switched off is
    /// not merely hidden — it is stopped, and a gesture must not be the one way
    /// back into something that was turned off.
    @discardableResult
    public func handleSwipe(_ direction: SwipeDirection) -> Bool {
        for feature in features where running.contains(feature.id) {
            if feature.handleSwipe(direction) { return true }
        }
        return false
    }

    /// The ids of the features currently running. Package-visible so the checks
    /// can prove that switching one off actually stops it.
    package var runningIDs: Set<String> { running }
}
