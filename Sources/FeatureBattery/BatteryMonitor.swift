import AppKit
import Foundation
import IOKit.ps
import HashNotchKit

/// A transient battery moment the island announces like the iPhone does:
/// plugging in shows a brief charge pill; dropping through 20% / 10% warns.
public enum BatteryEvent: Equatable {
    /// Power was connected. Deliberately not "started charging": at the instant
    /// the cable goes in, macOS reports external power but `IsCharging` is
    /// still false while the adapter is negotiated, and a moment later it may
    /// settle into charging, into a health hold, or into nothing at all if the
    /// battery is already full. The announcement says what just happened — you
    /// plugged it in — and the view reads the live state for the rest, so it
    /// corrects itself within a second rather than having to guess up front.
    case pluggedIn(Int)
    case lowBattery(Int)
    /// Reached full, or reached the level macOS is holding it at.
    case fullyCharged(Int)
    /// Unplugged — the counterpart to plugging in, so the pair reads as one
    /// idea rather than an announcement that only ever happens in one
    /// direction.
    case unplugged(Int)

    /// A warning is worth interrupting for and worth reading twice; the rest
    /// are pleasantries and should leave quickly. Package-visible so the checks
    /// can pin which announcements earn the longer stay.
    package var isWarning: Bool {
        if case .lowBattery = self { return true }
        return false
    }

    /// The symbol this announcement shows.
    ///
    /// A property of the EVENT, not of the live state, and that distinction is
    /// the whole point. The view used to pick this by asking what the battery
    /// was doing right then — and at the instant a cable goes in, macOS reports
    /// external power a beat before it reports charging, so the state is
    /// briefly "on hold" and plugging in was announced with a PAUSE symbol.
    /// Every time, on a Mac that then charged perfectly normally.
    ///
    /// An announcement is about the thing that just happened. You plugged it
    /// in, so it shows a bolt. What the battery then decides — charge, hold at
    /// 80% for its health, or nothing because it is already full — is a lasting
    /// fact rather than a moment, and the panel says which in words.
    package var symbolName: String {
        switch self {
        case .pluggedIn: return "bolt.fill"
        case .lowBattery: return "exclamationmark.triangle.fill"
        case .fullyCharged: return "checkmark.circle.fill"
        // A battery, filled to where the battery actually is — not a plug.
        //
        // Unplugging was drawn with a plug symbol, which names the thing that
        // just LEFT. At a glance that reads as "there is a charger here", the
        // opposite of what happened. What matters now is the battery, and how
        // much of it there is, so the symbol says exactly that.
        case .unplugged(let percent): return Self.batterySymbol(for: percent)
        }
    }

    /// Whether two announcements are the same KIND of thing, ignoring the level
    /// they carry.
    ///
    /// Used to swallow a repeat: the level may well have ticked between two
    /// reports of one physical event, and a repeat is a repeat whatever number
    /// rode along with it.
    package func isSameKind(as other: BatteryEvent) -> Bool {
        switch (self, other) {
        case (.pluggedIn, .pluggedIn), (.unplugged, .unplugged),
             (.lowBattery, .lowBattery), (.fullyCharged, .fullyCharged):
            return true
        default:
            return false
        }
    }

    /// The battery glyph closest to a given level, so the symbol and the number
    /// beside it never disagree.
    package static func batterySymbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// What the battery is doing, as the iPhone distinguishes it.
///
/// "Plugged in" and "charging" are not the same thing and macOS separates them
/// for a real reason: optimised charging parks the battery at around 80% for
/// its health, and Macs on permanent desk power sit there for weeks. Showing a
/// charging bolt for that is a small lie that makes people think something is
/// broken, so the state that says "connected, deliberately not filling" exists
/// on its own.
public enum BatteryState: Equatable {
    case discharging
    case charging
    /// On power, at 100%.
    case charged
    /// On power, deliberately not charging — usually optimised charging.
    case onHold
}

/// Reads charge level, charging state, and time remaining from IOKit power
/// sources — polled as a fallback, and refreshed instantly when the system
/// reports a power-source change (plug/unplug). Public API only.
@MainActor
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var percentage: Int = 0
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var minutesRemaining: Int?
    @Published public private(set) var hasBattery: Bool = false

    /// Whether a reading has been taken at all yet.
    ///
    /// Kept apart from `hasBattery` because the two are different claims and
    /// only one of them justifies hiding the indicator. `hasBattery` starts
    /// false, so reading a bare false as "this Mac has no battery" would hide
    /// the row on EVERY Mac for the instant before the first reading lands, and
    /// then pop it back in.
    @Published public private(set) var hasSampled: Bool = false

    /// True only once a reading has actually been taken AND it found no
    /// battery — an iMac, a Mac mini, a Mac Studio, a Mac Pro.
    ///
    /// The app is for Macs, not only for MacBooks, and on a desktop every part
    /// of this indicator is meaningless: no level, no time remaining, no time
    /// to full, no adapter. It showed anyway, dimmed, which reads as broken
    /// rather than as not applicable. So the whole indicator stands down, the
    /// same way AirPods does when nothing is connected.
    public var isUnavailable: Bool {
        Self.isUnavailable(hasSampled: hasSampled, hasBattery: hasBattery)
    }

    /// The rule on its own, so the checks can prove it never hides the
    /// indicator on a Mac that simply has not been read yet.
    package static func isUnavailable(hasSampled: Bool, hasBattery: Bool) -> Bool {
        hasSampled && !hasBattery
    }
    /// A short-lived announcement for the compact strip; nil when idle.
    @Published public private(set) var event: BatteryEvent?
    /// What the battery is doing — charging, held, full, or on its own.
    @Published public private(set) var state: BatteryState = .discharging
    /// Minutes until full while charging, when macOS is willing to estimate.
    @Published public private(set) var minutesToFull: Int?
    /// Whether macOS Low Power Mode is on. Read-only: macOS offers no public
    /// way to switch it, so the app reports it and can open the pane that does.
    @Published public private(set) var isLowPowerMode: Bool = false
    /// The connected adapter's rating in watts, when it reports one. Nil on
    /// battery, and nil for an adapter that declines to say.
    @Published public private(set) var adapterWatts: Int?

    /// The level this Mac is actually charging up to, when that is not 100%.
    ///
    /// Learned by watching rather than asked for. macOS offers no public way to
    /// read the charge limit — the 80% setting, or the ceiling optimised
    /// charging picks on its own — and the private registry keys that hint at
    /// it disagree between models and macOS versions. But the behaviour is
    /// unambiguous and needs no permission at all: when a Mac is on power and
    /// deliberately not charging, well short of full, the level it stopped at
    /// *is* the ceiling. Watching for that costs nothing and cannot be wrong
    /// about what it saw, where reading an undocumented key could be wrong
    /// quietly and forever.
    ///
    /// Nil until such a hold is seen, and cleared again the moment the battery
    /// climbs past it — because that is what a limit being raised or switched
    /// off looks like from here.
    @Published public private(set) var chargeCeiling: Int?

    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var powerSource: CFRunLoopSource?
    private var eventWork: DispatchWorkItem?
    /// The last announcement made, and when. Plugging in a USB-C charger can
    /// cross the same threshold twice while the adapter negotiates, and one
    /// cable should produce one announcement.
    private var lastAnnounced: (event: BatteryEvent, at: Date)?
    /// How long the same kind of announcement is treated as a repeat of the one
    /// before it rather than as news. Comfortably longer than a negotiation,
    /// far shorter than any genuine second plug-in.
    private static let repeatWindow: TimeInterval = 6
    private var settleSampler: PollingSampler?
    private var settleDeadline = Date.distantPast
    private var lowPowerObserver: NSObjectProtocol?
    private var lastCharging: Bool?
    private var lastPercentage: Int?
    private var lastState: BatteryState?

    public init() {}

    public func start(presence: LivePresence? = nil) {
        self.presence = presence

        // Instant plug/unplug reaction; the poll below is the fallback.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.sample() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        // Low Power Mode announces its own changes, so it never needs polling —
        // including when the user turns it on from the pane this app can open
        // for them, or when macOS turns it on by itself at 20%.
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                if self.isLowPowerMode != enabled { self.isLowPowerMode = enabled }
            }
        }

        // IOKit above reports every real change — plugged in, unplugged, each
        // step down — the instant it happens, so this poll is only a backstop
        // behind it. It does not need to be brisk, and a battery readout is the
        // last thing that should be spending battery.
        sampler = PollingSampler(interval: 60.0) { [weak self] in self?.sample() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        eventWork?.cancel()
        eventWork = nil
        stopSettling()
        event = nil
        presence?.setActive("battery", false)
    }

    /// Opens System Settings at the Battery pane.
    ///
    /// The default route to Low Power Mode, and the one that costs nothing.
    /// macOS has no public API to switch it, so this is one click from the
    /// panel to the switch that owns it.
    public static func openEnergySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Switches Low Power Mode directly, at the cost of an administrator
    /// password prompt. Only ever called when the user has opted in.
    ///
    /// `pmset` is the only thing on macOS that can set this and it requires
    /// root, so there is no version of this that happens quietly. The prompt is
    /// macOS's own — the password goes to the system's authorisation service
    /// and never passes through this app, which is the reason this is done with
    /// a one-shot privileged command rather than by installing a helper that
    /// would hold that privilege for the life of the app.
    ///
    /// The command is fixed text with a single interpolated 0 or 1 derived from
    /// a Bool, so there is nothing here a caller could steer.
    public static func setLowPowerMode(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        let value = enabled ? 1 : 0
        let script = """
        do shell script "/usr/bin/pmset -a lowpowermode \(value)" with administrator privileges
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let ok = NSAppleScript(source: script)?.executeAndReturnError(&error) != nil && error == nil
            if let error {
                // A cancelled password prompt is a decision, not a fault, and
                // reporting it as one would be noise on every second use.
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code != -128 {
                    FileHandle.standardError.write(Data(
                        "HashNotch: could not change Low Power Mode — \(error)\n".utf8
                    ))
                }
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// The low-battery threshold (20 or 10) that `new` crossed downward from
    /// `old`, if any. Pure so the checks can pin the behavior.
    package static func crossedLowThreshold(from old: Int, to new: Int) -> Int? {
        for threshold in [10, 20] where old > threshold && new <= threshold {
            return threshold
        }
        return nil
    }

    /// How quickly the connected adapter can fill this Mac.
    ///
    /// Judged on the adapter's own rating, which is the only figure available
    /// without measuring current draw over time — and the one that actually
    /// decides the answer, since a laptop charges as fast as what it is plugged
    /// into allows.
    ///
    /// The thresholds are coarse on purpose and drawn where they mean
    /// something. Below 20W is a phone charger: it will hold the machine up but
    /// barely fill it. From there to 60W is the everyday range, and that is
    /// where the stock adapter for a laptop of this size sits — calling it slow
    /// because it is not the biggest one Apple sells would be both wrong and
    /// discouraging about a charger that is doing its job. 60W and up is what
    /// Apple's own fast charging requires across the line.
    public enum ChargeSpeed: Equatable {
        case slow
        case standard
        case fast

        /// Ready to open a line, since that is where it is read.
        public var label: String {
            switch self {
            case .slow: return "Slow charge"
            case .standard: return "Charging"
            case .fast: return "Fast charge"
            }
        }

        package static func forWatts(_ watts: Int) -> ChargeSpeed? {
            guard watts > 0 else { return nil }
            if watts < 20 { return .slow }
            return watts < 60 ? .standard : .fast
        }
    }

    /// The speed of the connected adapter, when it reports a rating.
    public var chargeSpeed: ChargeSpeed? {
        adapterWatts.flatMap(ChargeSpeed.forWatts)
    }

    /// The ceiling to carry forward, given what was just seen.
    ///
    /// A hold below full teaches it; charging past a known ceiling unlearns it.
    /// Holds at or above `nearlyFull` are ignored, because a Mac sitting at
    /// 99% has simply finished, and calling that a limit would put "held at
    /// 99%" on the panel for the rest of the afternoon.
    ///
    /// Pure and package-visible: this is learned over minutes from hardware
    /// nobody can put in a given state on demand, so it is pinned by the checks
    /// rather than waited for.
    package nonisolated static func ceiling(
        after state: BatteryState,
        percentage: Int,
        known: Int?
    ) -> Int? {
        switch state {
        case .onHold where percentage < nearlyFull:
            return percentage
        case .charging:
            // Climbing past the old ceiling means it is no longer one.
            if let known, percentage > known { return nil }
            return known
        case .charged:
            return nil
        case .discharging, .onHold:
            return known
        }
    }

    /// Roughly how long until the ceiling, from the system's estimate of how
    /// long until full.
    ///
    /// macOS estimates time to 100%; there is no published figure for time to a
    /// limit. Scaling by how much of the remaining climb is actually wanted is
    /// the honest approximation available, and it holds up reasonably because
    /// the stretch below 80% is the steady part of a charge — the slow tail
    /// that would break a linear estimate lives above it, and is exactly the
    /// part a limit removes.
    ///
    /// Returns nil when there is nothing to scale or nothing left to climb.
    package nonisolated static func minutesToCeiling(
        minutesToFull: Int?,
        percentage: Int,
        ceiling: Int?
    ) -> Int? {
        guard let minutesToFull, minutesToFull > 0 else { return nil }
        guard let ceiling, ceiling < 100, percentage < ceiling else { return nil }
        let remaining = 100 - percentage
        guard remaining > 0 else { return nil }
        let wanted = ceiling - percentage
        return max(1, Int((Double(minutesToFull) * Double(wanted) / Double(remaining)).rounded()))
    }

    /// At or above this, a Mac on power has finished rather than been held.
    ///
    /// `nonisolated` because the pure helpers that read it are, and a constant
    /// has nothing to be isolated about. Without it the compiler is right to
    /// object: `ceiling(after:percentage:known:)` is nonisolated and was
    /// reaching a main-actor value, which Swift 6 rejects outright.
    package nonisolated static let nearlyFull = 95

    /// What the battery is doing, from the three things IOKit reports.
    ///
    /// Pure and package-visible so the checks can pin every combination without
    /// a Mac in that state — "plugged in at 80% and deliberately not charging"
    /// being the one that is hard to produce on demand and easy to get wrong.
    package static func state(
        onPower: Bool,
        isCharging: Bool,
        percentage: Int
    ) -> BatteryState {
        guard onPower else { return .discharging }
        if isCharging { return .charging }
        return percentage >= nearlyFull ? .charged : .onHold
    }

    /// How long an announcement stays.
    ///
    /// A warning earns longer than a pleasantry. "Charging" is a courtesy the
    /// user already knows about — they just plugged the cable in — while 10%
    /// is the one message in the app that must not be missed, and it is worth
    /// the extra seconds even on a surface built for glances.
    private static let noticeSeconds: TimeInterval = 4
    private static let warningSeconds: TimeInterval = 8

    /// Keep re-reading while the answer is still incomplete, and stop the
    /// moment it is not.
    ///
    /// A fixed burst of reads was the wrong shape. IOKit announces the cable
    /// and goes quiet, and what comes next has no schedule at all: charging may
    /// begin in a second or in a minute, and the estimate of time to full
    /// arrives whenever macOS is confident enough to give one — sometimes not
    /// for several minutes, and sometimes never, which is exactly what its own
    /// menu shows as "no estimate". A burst that ran for thirty seconds simply
    /// stopped watching before any of that happened and left the panel holding
    /// its first impression until the next minute-long poll came round.
    ///
    /// So the condition, not the clock, decides. Poll briskly while something
    /// is still expected, give up after a few minutes so a genuine health hold
    /// does not keep this running all afternoon, and stop immediately once
    /// there is nothing left to wait for.
    private static let settleInterval: TimeInterval = 4
    private static let settleWindow: TimeInterval = 240

    /// Development aid, off unless `HASHNOTCH_DEBUG` asks for it. What the
    /// system reports about power settles over minutes rather than at once, and
    /// none of it is visible from outside the app — so watching it arrive is
    /// the only way to tell "the app is stuck" from "macOS has not decided".
    private static let logsReadings =
        (ProcessInfo.processInfo.environment["HASHNOTCH_DEBUG"] ?? "").contains("battery")

    /// Nothing further is expected from the system.
    ///
    /// Pure and package-visible so the checks can pin it: the state this is
    /// deciding about lasts seconds and needs a cable in someone's hand to
    /// produce, which makes it exactly the thing that should not rely on being
    /// caught by eye.
    package nonisolated static func isSettled(
        state: BatteryState,
        minutesToFull: Int?
    ) -> Bool {
        switch state {
        case .discharging, .charged:
            return true
        case .charging:
            // Charging is only half the answer; the useful half is how long.
            return minutesToFull != nil
        case .onHold:
            // Might be a moment before charging starts, might be an all-day
            // hold at 80%. The window decides which.
            return false
        }
    }

    private var isSettled: Bool {
        Self.isSettled(state: state, minutesToFull: minutesToFull)
    }

    private func beginSettling() {
        settleDeadline = Date().addingTimeInterval(Self.settleWindow)
        guard settleSampler == nil else { return }
        let sampler = PollingSampler(interval: Self.settleInterval) { [weak self] in
            guard let self else { return }
            self.sample()
            if self.isSettled || Date() > self.settleDeadline { self.stopSettling() }
        }
        settleSampler = sampler
        sampler.start()
    }

    private func stopSettling() {
        settleSampler?.stop()
        settleSampler = nil
    }

    private func announce(_ newEvent: BatteryEvent) {
        // One cable, one announcement.
        //
        // "Charger connected" appeared twice in a row. Plugging in a USB-C
        // charger is not one clean transition: while the adapter is negotiated
        // macOS can report power arriving, dropping and arriving again within a
        // second or two, and each crossing looked like news. The physical event
        // happened once — the reporting of it stuttered.
        //
        // So the same KIND of announcement arriving again within a few seconds
        // is treated as the same thing being reported twice, and ignored. The
        // percentage is deliberately not compared: it may well have ticked in
        // between, and a repeat is a repeat whatever number rode along with it.
        if let last = lastAnnounced,
           last.event.isSameKind(as: newEvent),
           Date().timeIntervalSince(last.at) < Self.repeatWindow {
            return
        }
        lastAnnounced = (newEvent, Date())

        event = newEvent
        presence?.setActive("battery", true)
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.event = nil
                self?.presence?.setActive("battery", false)
            }
        }
        eventWork = work
        let seconds = newEvent.isWarning ? Self.warningSeconds : Self.noticeSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func sample() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            hasBattery = false
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let newPercentage = maximum > 0 ? Int((Double(current) / Double(maximum)) * 100.0) : current

            // Being on power and being charged BY it are separate facts, and
            // only IsCharging answers the second. Falling back to the power
            // state when it is missing is what made a Mac parked at 80% by
            // optimised charging claim it was charging.
            let onPower = (description[kIOPSPowerSourceStateKey as String] as? String)
                == kIOPSACPowerValue
            let newCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

            let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
            let newRemaining = (timeToEmpty ?? -1) > 0 ? timeToEmpty : nil
            let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int
            let newToFull = (timeToFull ?? -1) > 0 ? timeToFull : nil

            let newState = Self.state(
                onPower: onPower, isCharging: newCharging, percentage: newPercentage
            )

            // The adapter's rating, straight from the public power-source API.
            // Nil on battery, and nil for an adapter that reports no wattage —
            // in which case nothing about speed is claimed at all, rather than
            // a number being invented for the sake of having one.
            let watts = onPower
                ? (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
                    as? [String: Any])?[kIOPSPowerAdapterWattsKey] as? Int
                : nil
            if adapterWatts != watts { adapterWatts = watts }

            // Transient announcements, keyed on whether POWER is connected
            // rather than on the finer state.
            //
            // Keying them on the fine state is what swallowed the plug-in
            // alert. Plugging in fires the IOKit notification immediately, and
            // at that instant macOS reports external power while `IsCharging`
            // is still false — so the first sample lands on "held", not
            // "charging". The old rule only announced discharging → charging,
            // so the real sequence (discharging → held → charging) matched
            // nothing at all, while unplugging, which has no such intermediate
            // step, announced every time. Exactly the asymmetry that showed up
            // in use: pulling the cable spoke, putting it back said nothing.
            if let previous = lastState, previous != newState {
                let wasOnPower = previous != .discharging
                let isOnPower = newState != .discharging
                if isOnPower != wasOnPower {
                    announce(isOnPower ? .pluggedIn(newPercentage) : .unplugged(newPercentage))
                    // Watch closely for a few seconds afterwards.
                    //
                    // IOKit announces the cable, then goes quiet. The facts
                    // that matter settle AFTER that: `IsCharging` flips a second
                    // or two later once the adapter is negotiated, and the time
                    // to full is not estimated for a minute or more. With only
                    // the sixty-second backstop behind it, the panel sat there
                    // reading "held for battery health" while the menu bar said
                    // charging — right at the moment the user is looking at it,
                    // because plugging in is exactly when people glance.
                    beginSettling()
                } else if previous == .charging, newState == .charged || newState == .onHold {
                    // Still on power, but done filling.
                    announce(.fullyCharged(newPercentage))
                }
            }
            if !onPower, let lastPct = lastPercentage,
               Self.crossedLowThreshold(from: lastPct, to: newPercentage) != nil {
                announce(.lowBattery(newPercentage))
            }
            lastCharging = newCharging
            lastPercentage = newPercentage
            lastState = newState

            // Assign only on real change so identical samples cause no redraws.
            if percentage != newPercentage { percentage = newPercentage }
            if isCharging != newCharging { isCharging = newCharging }
            if state != newState { state = newState }
            let newCeiling = Self.ceiling(
                after: newState, percentage: newPercentage, known: chargeCeiling
            )
            if chargeCeiling != newCeiling { chargeCeiling = newCeiling }
            if Self.logsReadings {
                FileHandle.standardError.write(Data(
                    "[battery] \(newState) \(newPercentage)% charging=\(newCharging) toFull=\(newToFull.map(String.init) ?? "-") watts=\(watts.map(String.init) ?? "-") settling=\(settleSampler != nil)\n".utf8
                ))
            }
            if minutesRemaining != newRemaining { minutesRemaining = newRemaining }
            if minutesToFull != newToFull { minutesToFull = newToFull }
            if !hasBattery { hasBattery = true }
            if !hasSampled { hasSampled = true }
            return
        }

        // The power-source API answered and listed no battery. That is a real
        // answer — this is a Mac without one — as opposed to the guard above,
        // where the API itself failed and nothing can be concluded.
        if !hasSampled { hasSampled = true }
        if hasBattery { hasBattery = false }
    }
}
