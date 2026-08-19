import Foundation
import Combine

/// Saved configuration for one feature.
public struct FeatureConfig: Codable, Equatable {
    public var enabled: Bool
    public var placement: FeaturePlacement
    public var styleID: String
    public var order: Int

    public init(enabled: Bool, placement: FeaturePlacement, styleID: String, order: Int) {
        self.enabled = enabled
        self.placement = placement
        self.styleID = styleID
        self.order = order
    }
}

/// How the island looks. Every value here is wired to something visible — a
/// setting that changed nothing would be worse than no setting at all.
public struct AppearanceSettings: Codable, Equatable {
    /// The open panel's fill. The resting notch and the live strip are always
    /// solid black so they read as one piece with the hardware.
    public enum PanelFill: String, Codable, CaseIterable, Sendable {
        case glass
        case solid

        public var label: String {
            switch self {
            case .glass: return "Frosted glass"
            case .solid: return "Solid black"
            }
        }
    }

    /// How eager the island's motion is.
    public enum Motion: String, Codable, CaseIterable, Sendable {
        case calm
        case standard
        case lively

        public var label: String {
            switch self {
            case .calm: return "Calm"
            case .standard: return "Standard"
            case .lively: return "Lively"
            }
        }

        /// Multiplies every spring's response. Higher is slower and softer.
        public var responseScale: Double {
            switch self {
            case .calm: return 1.35
            case .standard: return 1.0
            case .lively: return 0.72
            }
        }
    }

    /// Solid black, not frosted.
    ///
    /// Frosted is the prettier screenshot and the worse default. The panel
    /// hangs off a physical notch that is solid black, so anything translucent
    /// makes the join visible: the notch stays black while the panel picks up
    /// whatever is behind it, and the illusion that the hardware itself opened
    /// is what pays for the whole design. Solid keeps them one piece on any
    /// wallpaper, and frosted is one click away for anyone who wants it.
    public var panelFill: PanelFill = .solid
    public var accentID: String = AccentColor.default.id
    public var motion: Motion = .standard
    /// The open panel's corner rounding, in points.
    public var panelCornerRadius: Double = 26

    /// The line drawn between one indicator and the next, in points.
    ///
    /// Adjustable because the right answer depends on the eye and the screen.
    /// A separator has to be strong enough to group what it divides and weak
    /// enough not to become one of the things being read — and where that line
    /// falls differs between somebody on a bright external display and somebody
    /// glancing at a laptop in the dark. Zero turns them off entirely, which is
    /// a legitimate preference rather than a broken state.
    ///
    /// The default is a half-point line at a third strength — thin and
    /// relatively bright, rather than thick and faint. Both group the rows, but
    /// a hairline reads as a rule between sections while a thicker band starts
    /// reading as a row of its own. Settled by looking at it on real hardware.
    public var separatorThickness: Double = 0.5
    /// How bright that line is, 0 to 1.
    public var separatorOpacity: Double = 0.35

    public static let separatorThicknessRange: ClosedRange<Double> = 0...4
    /// Ranges above the default in both directions, so the shipped setting is
    /// somewhere to move away from rather than a limit already reached.
    public static let separatorOpacityRange: ClosedRange<Double> = 0...0.5

    public init() {}
}

/// How often the AI token count is brought up to date.
///
/// Counting tokens means reading the transcripts the day has touched, and on a
/// busy machine that is tens of megabytes. The reader only looks at what has
/// been appended since it last ran, so none of these choices is expensive — but
/// how current a number needs to be is a judgement about the number, not about
/// the cost, and it belongs to whoever is reading it.
///
/// `never` does not mean the count stops working: it means nothing happens on a
/// clock, and the row is brought up to date when you ask it to.
public enum TokenScanInterval: String, Codable, CaseIterable, Sendable {
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case never

    /// How long between counts, or nil when only a manual refresh counts.
    public var seconds: TimeInterval? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .thirtyMinutes: return 1_800
        case .oneHour: return 3_600
        case .never: return nil
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: return "Every minute"
        case .fiveMinutes: return "Every 5 minutes"
        case .tenMinutes: return "Every 10 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour: return "Every hour"
        case .never: return "Only when I ask"
        }
    }
}

/// The stretch of time the "data used" figures are counted over.
///
/// A total of bytes means nothing without the period it covers, and which
/// period is useful is a question about the person rather than about the
/// network: a data plan is monthly, a tethered afternoon is daily, and
/// somebody watching one particular job wants to start the count themselves.
///
/// The figures for all three come from the same record of daily totals, so
/// changing this reads a different span of what is already known rather than
/// starting again from zero.
public enum NetworkUsagePeriod: String, Codable, CaseIterable, Sendable {
    case today
    case thisMonth
    case sinceReset

    public var label: String {
        switch self {
        case .today: return "Today"
        case .thisMonth: return "This month"
        case .sinceReset: return "Since I reset it"
        }
    }

    /// How the panel names the span beside the figures.
    public var caption: String {
        switch self {
        case .today: return "today"
        case .thisMonth: return "this month"
        case .sinceReset: return "since reset"
        }
    }
}

/// How alerts behave.
public struct AlertSettings: Codable, Equatable {
    /// How long a "something finished" notice stays on the notch. The poster
    /// suggests a duration; this is the reader's preference, and the reader
    /// wins — it is your notch.
    public var noticeSeconds: Double = 3
    /// Whether an alert that is asking for something — a permission prompt —
    /// waits for you instead of leaving on its own.
    public var requestsWaitForYou: Bool = true

    public init() {}
}

/// The whole persisted document. Unknown keys in an older saved document (e.g.
/// the removed layout block) are ignored on decode, and missing ones fall back
/// to their defaults, so a document written by an older build still loads.
private struct SettingsDocument: Codable {
    var features: [String: FeatureConfig]
    var launchAtLogin: Bool
    var batterySaver: Bool?
    var canSwitchLowPowerMode: Bool?
    var canPressMediaKeys: Bool?
    var appearance: AppearanceSettings?
    var alerts: AlertSettings?
    var tokenScanInterval: TokenScanInterval?
    var networkUsagePeriod: NetworkUsagePeriod?
    /// Hand-made position corrections, keyed by display.
    var adjustments: [String: IslandAdjustment]?
    /// Which music services may be asked for a cover. Absent means all of them.
    var artworkServices: [String: Bool]?
    /// Whether the user has seen what the indicators read and agreed to it.
    /// Optional because documents written before this existed have no opinion,
    /// and those are installs that already made their choices — they are read
    /// as having agreed rather than being asked again.
    var hasAcceptedReading: Bool?
}

/// The single source of truth for user customization, backed by `UserDefaults`.
///
/// Features and the HUD read from here; the settings window writes to it. Any
/// change is saved automatically. The store is intentionally the only stateful
/// place — features stay stateless about configuration.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var features: [String: FeatureConfig] {
        didSet { featuresGeneration &+= 1 }
    }

    /// How often a fresh install counts AI tokens.
    ///
    /// Half-hourly rather than every five minutes. The count is cheap — only
    /// what the tools have appended since last time is read — but it is a
    /// figure that moves over a working session, not second to second, and a
    /// number that visibly changes while nothing is happening invites attention
    /// it does not deserve. Anyone who wants it livelier has the choice, down
    /// to every minute.
    ///
    /// Named once so the value and its fallback cannot drift apart, and so the
    /// checks can pin it.
    public static let defaultTokenScanInterval: TokenScanInterval = .thirtyMinutes

    /// What a fresh install counts data used over.
    ///
    /// The day, not the month. A daily figure is one anybody can check against
    /// their own memory of what they did — a month's is a number you have to
    /// take on trust — and it is the one that is right on the first day, when a
    /// monthly figure would be counting from part-way through a month it cannot
    /// see the beginning of.
    ///
    /// Named once so the value and its fallback cannot drift apart, and so the
    /// checks can pin it.
    /// `nonisolated` so a feature can name it as a default argument without
    /// hopping to the main actor to read a constant.
    public nonisolated static let defaultNetworkUsagePeriod: NetworkUsagePeriod = .today

    /// Bumped whenever the stored feature configuration changes.
    ///
    /// Exists so anything derived from `features` — the island's draw order,
    /// above all — can tell in a single integer comparison whether its cached
    /// answer is still good. The island's body is evaluated on every published
    /// change from every monitor, which during an opening animation is dozens of
    /// times a second; re-deriving an order that can only change when a setting
    /// changes was pure waste, and comparing the whole dictionary to find that
    /// out would have been its own cost.
    public private(set) var featuresGeneration: Int = 0

    @Published public var launchAtLogin: Bool
    /// Halves how often everything samples. Features re-read this when they
    /// restart, which the app does as soon as it changes.
    @Published public var batterySaver: Bool = false
    /// Whether the panel may switch Low Power Mode itself, which costs an
    /// administrator password every single time.
    ///
    /// Off by default, and deliberately so. macOS has no public way to change
    /// this setting; the only thing that can is a root command, so switching it
    /// from the panel means macOS asking for a password on every toggle. That
    /// is a fair trade for someone who wants it and a nasty surprise for
    /// everyone else, which is exactly what an opt-in is for. With this off the
    /// panel still shows the state and offers one click to the pane that owns
    /// it.
    @Published public var canSwitchLowPowerMode: Bool = false
    /// Whether the panel's media buttons may drive a browser by pressing the
    /// keyboard's media keys.
    ///
    /// Off by default, because it needs Accessibility — the one permission this
    /// app otherwise never asks for. Without it the buttons still work for
    /// Spotify and Apple Music, which have scripting interfaces; a video in a
    /// browser simply cannot be reached, since the system's media channel
    /// accepts commands for it and does nothing.
    @Published public var canPressMediaKeys: Bool = false
    @Published public var appearance = AppearanceSettings()
    @Published public var alerts = AlertSettings()
    /// How often the AI token count is brought up to date.
    @Published public var tokenScanInterval: TokenScanInterval = SettingsStore.defaultTokenScanInterval
    /// The span the data-used figures cover.
    @Published public var networkUsagePeriod: NetworkUsagePeriod = SettingsStore.defaultNetworkUsagePeriod
    /// Position corrections per display. A display with no entry is automatic.
    @Published public var adjustments: [String: IslandAdjustment] = [:]

    /// Which music services may be asked for a cover, by `settingKey`.
    ///
    /// Absent means yes. A service added in a later version is therefore on for
    /// an existing install, which is the same rule the feature list follows —
    /// the alternative is a new service that silently never works because a
    /// saved document written before it existed has no opinion about it.
    @Published public var artworkServices: [String: Bool] = [:]

    public func isArtworkEnabled(_ service: ArtworkService) -> Bool {
        artworkServices[service.settingKey] ?? true
    }

    public func setArtworkEnabled(_ service: ArtworkService, _ enabled: Bool) {
        artworkServices[service.settingKey] = enabled
    }

    /// The set the download policy runs on. Kept in one place so the policy and
    /// the switches can never disagree about what is allowed.
    public var enabledArtworkServiceIDs: Set<String> {
        Set(ArtworkService.all.filter(isArtworkEnabled).map(\.id))
    }

    /// The correction for one display, or an untouched one.
    public func adjustment(for displayKey: String) -> IslandAdjustment {
        adjustments[displayKey] ?? IslandAdjustment()
    }

    public func setAdjustment(_ adjustment: IslandAdjustment, for displayKey: String) {
        if adjustment.isAutomatic {
            adjustments.removeValue(forKey: displayKey)
        } else {
            adjustments[displayKey] = adjustment.clamped
        }
    }

    /// Multiplies every sampling interval. Kept here rather than in each
    /// monitor so "sample less often" means one number in one place.
    public var samplingScale: Double { batterySaver ? 2 : 1 }

    /// The accent colour, resolved from the stored id.
    public var accent: AccentColor { AccentColor.named(appearance.accentID) }

    /// True when there was no saved configuration to load (i.e. first ever run).
    /// Used to show the settings window once so the app is easy to find.
    public let isFirstRun: Bool

    /// Whether the user has been shown what the indicators read and agreed to
    /// it. Nothing that reads a file, runs a subprocess, or can raise a macOS
    /// permission prompt starts until this is true.
    ///
    /// Stored rather than derived so it survives a relaunch, and separate from
    /// `isFirstRun` because they answer different questions: `isFirstRun` asks
    /// whether there were settings to load, this asks whether anybody said yes.
    ///
    /// **An existing install counts as having agreed.** Someone already running
    /// the app chose their indicators long ago, and putting a consent screen in
    /// front of them on an update would be asking a question they have already
    /// answered — so the carry-over path below sets this true. Only a genuinely
    /// new install is asked.
    @Published public var hasAcceptedReading: Bool = false

    private let defaults: UserDefaults
    /// v3, not v2, and the bump is doing real work.
    ///
    /// The app has now carried three names, and the current one is the same as
    /// the FIRST one — so the obvious key, `hashnotch.settings.v2`, is a key
    /// this app has already used and abandoned once. Writing today's settings
    /// back into it would make the newest file indistinguishable from the
    /// oldest, and a machine that has been through both names has both on disk.
    /// Reading the old one would then quietly restore choices the user changed
    /// a rename ago. A fresh key means "written by a version that knows about
    /// all three names", which is exactly the distinction the carry-over below
    /// needs to make.
    private let storageKey = "hashnotch.settings.v3"
    private var saveCancellable: AnyCancellable?

    /// Where settings lived under each name this app has had, **newest first**.
    ///
    /// Preferences are keyed by bundle identifier, so without this an existing
    /// install would silently come back with every choice reset.
    ///
    /// The order is the whole point rather than a detail. Someone who has run
    /// this app since its first name has an entry under both of these, and only
    /// one of them is what they last chose. Newest first means the more recent
    /// name always wins, and the older one is only ever reached by somebody who
    /// never had the newer.
    private static let legacyLocations: [(key: String, domain: String)] = [
        ("hashdisland.settings.v2", "com.hashdisland.app"),
        ("hashnotch.settings.v2", "com.hashnotch.app"),
    ]

    /// `legacyDefaults` is where settings written under the app's previous name
    /// are looked for. It is a parameter purely so the checks can prove the
    /// carry-over works without touching the real preferences.
    public init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults

        // Carried-over settings come from the app's previous name and are
        // written back under the new key by the save below, so that path is
        // taken exactly once.
        let document = Self.load(key: storageKey, from: defaults)
            ?? Self.loadLegacy(explicit: legacyDefaults, running: defaults)

        if let document {
            self.features = document.features
            self.launchAtLogin = document.launchAtLogin
            self.batterySaver = document.batterySaver ?? false
            self.canSwitchLowPowerMode = document.canSwitchLowPowerMode ?? false
            self.canPressMediaKeys = document.canPressMediaKeys ?? false
            self.appearance = document.appearance ?? AppearanceSettings()
            self.alerts = document.alerts ?? AlertSettings()
            self.tokenScanInterval = document.tokenScanInterval ?? SettingsStore.defaultTokenScanInterval
            self.networkUsagePeriod = document.networkUsagePeriod ?? SettingsStore.defaultNetworkUsagePeriod
            self.adjustments = (document.adjustments ?? [:]).mapValues(\.clamped)
            self.artworkServices = document.artworkServices ?? [:]
            self.isFirstRun = false
            // Absent in a document written before this existed, which is
            // exactly an install that predates the question — and one that
            // already chose its indicators. Asking it now would be asking
            // something already answered.
            self.hasAcceptedReading = document.hasAcceptedReading ?? true
        } else {
            self.features = [:]
            self.launchAtLogin = false
            self.isFirstRun = true
            self.hasAcceptedReading = false
        }

        // Persist on any change, coalesced to the next runloop tick.
        saveCancellable = objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.save() }
            }

        // Write the carried-over settings straight away, so they survive even
        // if the app is quit before anything else changes.
        if !isFirstRun, defaults.data(forKey: storageKey) == nil { save() }
    }

    private static func load(key: String, from defaults: UserDefaults) -> SettingsDocument? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SettingsDocument.self, from: data)
    }

    /// Settings saved under one of the app's previous names, newest name first.
    ///
    /// Each is checked in the running defaults first (an unbundled `swift run`
    /// build shares one domain, and the app's CURRENT domain is also where the
    /// oldest name's key would sit, since the name has come back around), then
    /// in that name's own bundle domain, which is where a real installed copy
    /// kept them.
    private static func loadLegacy(
        explicit: UserDefaults?,
        running: UserDefaults
    ) -> SettingsDocument? {
        for location in legacyLocations {
            if let explicit {
                if let document = load(key: location.key, from: explicit) { return document }
                continue
            }
            if let document = load(key: location.key, from: running) { return document }
            if let legacy = UserDefaults(suiteName: location.domain),
               let document = load(key: location.key, from: legacy) {
                return document
            }
        }
        return nil
    }

    // MARK: Reading

    /// The stored config for a feature, or a sensible default derived from the
    /// feature itself the first time it is seen.
    public func config(for feature: NotchFeature, index: Int) -> FeatureConfig {
        if let stored = features[feature.id] { return stored }
        return FeatureConfig(
            enabled: true,
            placement: feature.placement,
            styleID: feature.displayOptions.first?.id ?? "default",
            order: index
        )
    }

    public func isEnabled(_ id: String) -> Bool {
        features[id]?.enabled ?? true
    }

    public func style(for id: String) -> String {
        features[id]?.styleID ?? "default"
    }

    // MARK: Writing

    /// Ensure every known feature has a stored config (called once at launch so
    /// the settings UI has something to bind to).
    public func seed(features list: [NotchFeature]) {
        for (index, feature) in list.enumerated() where features[feature.id] == nil {
            features[feature.id] = config(for: feature, index: index)
        }
    }

    /// Put the look of the island back to the way it ships.
    ///
    /// Only the appearance values — accent, fill, motion, rounding, separators.
    /// Which indicators are on, where they sit, and everything on the other
    /// pages are left exactly as they are, because someone reaching for the
    /// button under the appearance controls is asking about what they can see
    /// on that page, not about their whole configuration.
    public func resetAppearance() {
        appearance = AppearanceSettings()
    }

    /// Put every stored choice back to the way the app ships.
    ///
    /// The feature list is REBUILT rather than emptied. `seed` only fills in
    /// ids it has never seen, and it runs once at launch — so clearing the
    /// dictionary here would leave the settings window bound to nothing until
    /// the next start, with every indicator reading as absent rather than as
    /// its default. Writing a fresh default entry for each descriptor keeps the
    /// store complete at every moment.
    ///
    /// `placement` is carried over rather than reset. It is the feature's own
    /// declaration of where it can appear, not a choice the user ever makes,
    /// and the settings UI stopped offering it long ago.
    ///
    /// Two things are deliberately NOT reset:
    ///
    /// - **Consent.** `hasAcceptedReading` stays true. `isFirstRun` is fixed
    ///   when the store is built, so the opening window cannot be shown again
    ///   without a relaunch — while `syncRunning` refuses to start anything at
    ///   all until consent is given. Clearing it here would stop every
    ///   indicator and leave no way on screen to say yes again.
    /// - **Open at login.** That lives in the system, not in this file, and the
    ///   caller puts it back through `LoginItem` so the stored value and what
    ///   macOS actually does cannot disagree.
    public func resetAll(features descriptors: [FeatureDescriptor]) {
        appearance = AppearanceSettings()
        alerts = AlertSettings()
        tokenScanInterval = Self.defaultTokenScanInterval
        networkUsagePeriod = Self.defaultNetworkUsagePeriod
        batterySaver = false
        canSwitchLowPowerMode = false
        canPressMediaKeys = false
        adjustments = [:]
        artworkServices = [:]

        var rebuilt: [String: FeatureConfig] = [:]
        for (index, descriptor) in descriptors.enumerated() {
            rebuilt[descriptor.id] = FeatureConfig(
                enabled: true,
                placement: features[descriptor.id]?.placement ?? .expanded,
                styleID: descriptor.options.first?.id ?? "default",
                order: index
            )
        }
        features = rebuilt
    }

    public func update(_ id: String, _ mutate: (inout FeatureConfig) -> Void) {
        guard var config = features[id] else { return }
        mutate(&config)
        features[id] = config
    }

    /// Rewrite the display order from a list of ids, top to bottom.
    ///
    /// Order is stored per feature rather than as a list so that a feature
    /// added in a later version simply appears at its default position instead
    /// of being lost from a saved list that predates it.
    public func setOrder(_ ids: [String]) {
        for (index, id) in ids.enumerated() {
            update(id) { $0.order = index }
        }
    }


    /// Force an immediate synchronous save (the automatic save is coalesced to
    /// the next runloop tick; tests and shutdown use this).
    public func flush() { save() }

    private func save() {
        let document = SettingsDocument(
            features: features,
            launchAtLogin: launchAtLogin,
            batterySaver: batterySaver,
            canSwitchLowPowerMode: canSwitchLowPowerMode,
            canPressMediaKeys: canPressMediaKeys,
            appearance: appearance,
            alerts: alerts,
            tokenScanInterval: tokenScanInterval,
            networkUsagePeriod: networkUsagePeriod,
            adjustments: adjustments,
            artworkServices: artworkServices,
            hasAcceptedReading: hasAcceptedReading
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
