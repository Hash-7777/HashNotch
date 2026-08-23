import Foundation
import HashNotchKit

/// Reads live upload/download throughput by diffing the kernel's per-interface
/// byte counters once a second. Public API only.
///
/// The counters come from `sysctl(NET_RT_IFLIST2)`, not `getifaddrs` — see
/// `NetworkInterfaces.read`, which says why the obvious call is the wrong one.
@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var uploadBytesPerSec: Double = 0
    @Published public private(set) var downloadBytesPerSec: Double = 0
    /// Recent rates, oldest first, for the graph styles.
    @Published public private(set) var upHistory: [Double] = []
    @Published public private(set) var downHistory: [Double] = []
    /// How much has gone through the network over the span the settings ask
    /// for. Counted from the same readings the speed is measured from.
    @Published package private(set) var usage = NetworkUsageTotals()
    /// The programs that used the most over that same span, biggest first.
    ///
    /// Empty when the breakdown is switched off, and empty until a second
    /// reading has been taken — a counter on its own says nothing, and the
    /// first one is only a starting point to measure from.
    @Published package private(set) var topApps: [AppUsageShare] = []

    /// Half a minute of samples. Held here rather than in the view so the shape
    /// survives a redraw.
    private static let historyLength = 30

    /// What the graphs are drawn against: the busiest moment still in view, or
    /// a floor of 1 MB/s — otherwise an idle link has its own noise magnified
    /// to fill the frame and looks like a storm.
    public var graphCeiling: Double {
        max(1_000_000, (upHistory + downHistory).max() ?? 0)
    }

    private static let interval: TimeInterval = 1.0
    /// The interval actually in use, which battery saver stretches. The
    /// staleness rule is measured against this rather than the nominal value,
    /// so a saver-paced reading is not mistaken for an ancient one.
    private var effectiveInterval: TimeInterval = interval

    private var sampler: VisibleSampler?
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastTime: TimeInterval = 0

    /// How often the ledger is brought up to date when nothing is watching.
    ///
    /// Unlike the speed, a running total has to keep counting whether or not
    /// the panel is open — a figure for the day that only counted the moments
    /// somebody was looking at it would be worthless. This is the cheapest
    /// reading in the app: one call into the kernel, in process, no subprocess
    /// and no permission, and a minute of it costs less than a single one of
    /// the media polls that run all day.
    ///
    /// A minute is also the most that can be lost if the app is killed rather
    /// than quit, and the least that is worth waking a sleeping Mac for.
    private static let usageInterval: TimeInterval = 60

    private var usageSampler: PollingSampler?
    private var ledger = NetworkUsageLedger()
    private var period: NetworkUsagePeriod = SettingsStore.defaultNetworkUsagePeriod
    private var defaults: UserDefaults = .standard
    private var lastPersist: Date = .distantPast

    /// How many programs the panel is offered.
    ///
    /// Three. Six filled the panel with names nobody recognises — the machine's
    /// own background services are always in the list and are never the answer
    /// to "where did my data go", so the rows that matter were being pushed
    /// down by rows that do not. Three is the shape of a real answer: the one
    /// that dominated, and the two worth comparing it with. Well inside the
    /// dozen a day keeps, so the list never runs out before the record does.
    package static let topAppCount = 3

    private var appLedger = AppUsageLedger()
    private var showsApps = SettingsStore.defaultNetworkShowsApps
    /// The last time the per-process counters were asked for.
    ///
    /// The totals are folded every second while the panel is open, because the
    /// figure somebody is looking at should climb while they look at it. That
    /// reading is one call into the kernel. This one is a subprocess, so it
    /// stays on the minute whatever the panel is doing — a breakdown that
    /// changes place every second would be unreadable even if it were free.
    private var lastAppRead: Date = .distantPast

    public init() {}

    public func start(
        visibility: PanelVisibility,
        scale: Double = 1,
        period: NetworkUsagePeriod = SettingsStore.defaultNetworkUsagePeriod,
        showsApps: Bool = SettingsStore.defaultNetworkShowsApps,
        defaults: UserDefaults = .standard
    ) {
        self.period = period
        self.showsApps = showsApps
        self.defaults = defaults
        ledger = NetworkUsageStore.load(from: defaults) ?? NetworkUsageLedger()
        appLedger = NetworkAppUsageStore.load(from: defaults) ?? AppUsageLedger()

        let reading = NetworkInterfaces.read()
        let counters = NetworkInterfaces.totalBytes(reading)
        lastRx = counters.received
        lastTx = counters.sent
        lastTime = Date().timeIntervalSinceReferenceDate
        effectiveInterval = Self.interval * scale

        // The first fold of a launch carries no bytes of its own — every
        // interface is met where its counters currently stand — but it does
        // catch a counter that restarted while the app was not running, which
        // is what a restart of the Mac looks like from here.
        fold(reading: reading, now: Date())

        // The breakdown's own first reading, for the same reason: it carries no
        // bytes, and it is what every later one is measured against. Taken at
        // launch rather than waiting a minute so the first minute of a session
        // is counted like every other one.
        foldApps(now: Date())

        // Throughput is only ever drawn in the panel, so it is measured only
        // while the panel is open.
        sampler = VisibleSampler(interval: effectiveInterval, visibility: visibility) { [weak self] in
            self?.sample()
        }
        sampler?.start()

        // The total, unlike the speed, keeps counting with the panel shut.
        usageSampler = PollingSampler(interval: Self.usageInterval * scale) { [weak self] in
            self?.sampleUsage()
        }
        usageSampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        usageSampler?.stop()
        usageSampler = nil
        // Stopping is a sleep, a display change, or the indicator being
        // switched off — all moments after which this may not run again, so
        // what has been counted is written down rather than left in memory.
        sampleUsage(persist: true)
    }

    /// Follows the settings while running, so choosing a different span shows
    /// the answer straight away rather than at the next reading.
    public func setPeriod(_ period: NetworkUsagePeriod) {
        guard period != self.period else { return }
        self.period = period
        publishUsage(now: Date())
    }

    /// Follows the breakdown's own switch while running.
    ///
    /// Switching it off stops the asking, not just the drawing: no subprocess
    /// runs, and what has already been recorded is thrown away rather than kept
    /// out of sight. Switching it on starts from a fresh baseline for the same
    /// reason the app does at launch — the counters have been running while
    /// nobody was reading them, and their current values are history.
    public func setShowsApps(_ shows: Bool) {
        guard shows != showsApps else { return }
        showsApps = shows
        if shows {
            appLedger = AppUsageLedger()
            foldApps(now: Date())
        } else {
            appLedger = AppUsageLedger()
            NetworkAppUsageStore.clear(from: defaults)
            topApps = []
        }
    }

    /// Starts the count again, for the span that is counted from a reset.
    ///
    /// The day-by-day record is left alone: today and this month are read from
    /// the same days and have every right to them.
    public func resetUsage() {
        ledger = NetworkUsageMath.afterReset(ledger, now: Date())
        appLedger = NetworkAppUsageMath.afterReset(appLedger, now: Date())
        NetworkUsageStore.save(ledger, to: defaults)
        NetworkAppUsageStore.save(appLedger, to: defaults)
        lastPersist = Date()
        publishUsage(now: Date())
    }

    /// Reads the counters, folds them in, and writes the record down.
    private func sampleUsage(persist: Bool = true) {
        let now = Date()
        fold(reading: NetworkInterfaces.read(now: now), now: now)
        foldApps(now: now)
        if persist { persistIfDue(now: now) }
    }

    private func fold(reading: [String: InterfaceBytes], now: Date) {
        let before = NetworkUsageMath.totals(ledger, period: period, now: now)
        ledger = NetworkUsageMath.folded(ledger, reading: reading, now: now)
        publishUsage(now: now)
        Self.usageTrace(before: before, after: usage, reading: reading, now: now)
    }

    /// Asks which programs the traffic went through, at most once a minute.
    ///
    /// Nothing is asked at all while the breakdown is switched off — the
    /// subprocess is not started, so "off" is a thing the app does not do
    /// rather than a thing it does not show.
    private func foldApps(now: Date) {
        guard showsApps else { return }
        guard now.timeIntervalSince(lastAppRead) >= Self.usageInterval
            || lastAppRead == .distantPast else { return }
        lastAppRead = now
        guard let reading = AppTrafficReader.read() else { return }
        appLedger = NetworkAppUsageMath.folded(appLedger, reading: reading, now: now)
        publishUsage(now: now)
    }

    /// Development aid, off unless `HASHNOTCH_DEBUG=usage` asks for it. Every
    /// fold, what it added, and what the counters read when it did — the only
    /// way to tell a total climbing too fast apart from counters that are, and
    /// to see how many folds are happening at all.
    private static func usageTrace(
        before: NetworkUsageTotals,
        after: NetworkUsageTotals,
        reading: [String: InterfaceBytes],
        now: Date
    ) {
        guard (ProcessInfo.processInfo.environment["HASHNOTCH_DEBUG"] ?? "").contains("usage") else { return }
        let counters = reading.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.received)/\($0.value.sent)" }
            .joined(separator: " ")
        let addedIn = after.received &- before.received
        let addedOut = after.sent &- before.sent
        let stamp = Int(now.timeIntervalSince1970)
        let line = "[usage] \(stamp) added in \(addedIn) out \(addedOut)"
            + " | total in \(after.received) out \(after.sent) | \(counters)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func publishUsage(now: Date) {
        let totals = NetworkUsageMath.totals(ledger, period: period, now: now)
        if totals != usage { usage = totals }

        // The breakdown is summed over the SAME span start the totals use, so
        // the two figures shown together are always answering one question.
        let shares = showsApps
            ? NetworkAppUsageMath.topApps(
                appLedger,
                from: NetworkUsageMath.spanStart(period, ledger: ledger, now: now),
                limit: Self.topAppCount)
            : []
        if shares != topApps { topApps = shares }
    }

    /// Writes at most once a minute however often the counters are read.
    ///
    /// With the panel open the ledger is folded every second, because the
    /// figure people are looking at should climb while they look at it. Saving
    /// on every one of those would be a preference write a second for as long
    /// as the panel is up, to record a number that has moved by a few kilobytes.
    private func persistIfDue(now: Date) {
        guard now.timeIntervalSince(lastPersist) >= Self.usageInterval else { return }
        NetworkUsageStore.save(ledger, to: defaults)
        if showsApps { NetworkAppUsageStore.save(appLedger, to: defaults) }
        lastPersist = now
    }

    /// Whether the previous reading is too old to diff against.
    ///
    /// Throughput is a difference over time, so it is only meaningful between
    /// two readings taken a moment apart. After the panel has been shut — or
    /// the Mac asleep — the last reading can be hours old, and diffing against
    /// it would report an average over that whole period as if it were the
    /// speed right now. Such a reading is thrown away and used as the new
    /// baseline instead, costing one interval before the first number appears.
    ///
    /// Pure and package-visible so the checks can pin it.
    package nonisolated static func isStaleBaseline(
        dt: TimeInterval,
        interval: TimeInterval
    ) -> Bool {
        dt > interval * 3
    }

    private func sample() {
        let sampledAt = Date()
        let now = sampledAt.timeIntervalSinceReferenceDate
        let dt = max(0.001, now - lastTime)
        let reading = NetworkInterfaces.read(now: sampledAt)
        let counters = NetworkInterfaces.totalBytes(reading)

        // The same reading serves both figures: the speed below, and the
        // running total, which climbs while the panel is open rather than
        // waiting for the minute timer.
        fold(reading: reading, now: sampledAt)
        persistIfDue(now: sampledAt)

        guard !Self.isStaleBaseline(dt: dt, interval: effectiveInterval) else {
            lastRx = counters.received
            lastTx = counters.sent
            lastTime = now
            return
        }

        // Counters can wrap (32-bit) or reset; treat a decrease as zero delta.
        let dRx = counters.received >= lastRx ? counters.received - lastRx : 0
        let dTx = counters.sent >= lastTx ? counters.sent - lastTx : 0

        let newDownload = Double(dRx) / dt
        let newUpload = Double(dTx) / dt

        // Only publish when the displayed MB/s value actually changes, so an idle
        // link (0.00) triggers no SwiftUI redraws at all.
        if Formatters.megabytesPerSecond(newDownload) != Formatters.megabytesPerSecond(downloadBytesPerSec) {
            downloadBytesPerSec = newDownload
        }
        if Formatters.megabytesPerSecond(newUpload) != Formatters.megabytesPerSecond(uploadBytesPerSec) {
            uploadBytesPerSec = newUpload
        }

        // The history takes every sample, including the ones too small to
        // change the printed number — a graph of only the changes would be a
        // graph with the quiet parts cut out.
        upHistory.append(newUpload)
        downHistory.append(newDownload)
        if upHistory.count > Self.historyLength {
            upHistory.removeFirst(upHistory.count - Self.historyLength)
            downHistory.removeFirst(downHistory.count - Self.historyLength)
        }

        lastRx = counters.received
        lastTx = counters.sent
        lastTime = now
    }
}
