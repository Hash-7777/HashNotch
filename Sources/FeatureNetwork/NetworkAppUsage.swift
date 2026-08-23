import Foundation
import HashNotchKit

/// Which programs the traffic went through, kept the same way the totals are.
///
/// The totals beside them answer "how much"; this answers "what was it". A
/// figure of nine gigabytes today is not actionable on its own — it becomes
/// actionable the moment it says that eight of them were one program.
///
/// This is a different KIND of reading from everything else in the network
/// feature, and it is worth being plain about the difference. The byte counters
/// are per interface: they know how much went past and nothing whatever about
/// which program sent it. This asks macOS a second question — how much has each
/// of your own processes sent and received — so the app now knows the names of
/// the programs on this Mac that use the network. That is why it has its own
/// switch, and why turning it off stops the asking rather than hiding the
/// answer. It still leaves the Mac in every other respect: no address, no site,
/// no packet, and nothing about any of it goes anywhere.
///
/// The bookkeeping mirrors `NetworkUsage` deliberately. Both are counters that
/// only ever grow, turned into a day-by-day record by taking the difference
/// between one reading and the next, so the two figures shown side by side are
/// built the same way and cannot drift apart in their arithmetic.

/// What one process's counters read when they were last looked at.
///
/// Keyed by process rather than by program, because a counter belongs to a
/// running process: two runs of the same program are two counters, each
/// starting again at zero.
package struct ProcessBytes: Codable, Equatable, Sendable {
    package var received: UInt64
    package var sent: UInt64
    package var seenAt: Date

    package init(received: UInt64, sent: UInt64, seenAt: Date) {
        self.received = received
        self.sent = sent
        self.seenAt = seenAt
    }
}

/// One program's share of one day.
package struct AppBytes: Codable, Equatable, Sendable {
    package var received: UInt64
    package var sent: UInt64

    package init(received: UInt64 = 0, sent: UInt64 = 0) {
        self.received = received
        self.sent = sent
    }

    package var total: UInt64 { received &+ sent }
}

/// One day, broken down by program.
package struct AppDayUsage: Codable, Equatable, Sendable {
    package var day: Date
    package var apps: [String: AppBytes]

    package init(day: Date, apps: [String: AppBytes] = [:]) {
        self.day = day
        self.apps = apps
    }
}

/// The mark left behind when the count is started again, mirroring
/// `UsageReset` so the breakdown and the total it sits under agree about what
/// "since reset" means.
package struct AppUsageReset: Codable, Equatable, Sendable {
    package var at: Date
    package var dayApps: [String: AppBytes]

    package init(at: Date, dayApps: [String: AppBytes]) {
        self.at = at
        self.dayApps = dayApps
    }
}

/// The whole record: the days, and where each process's counters had got to.
package struct AppUsageLedger: Codable, Equatable, Sendable {
    package var days: [AppDayUsage]
    package var lastSeen: [String: ProcessBytes]
    /// Whether anything has been read yet.
    ///
    /// The very first reading is a baseline and counts nothing, because every
    /// process already running has a counter holding traffic from before
    /// anybody was watching. Every reading after it can trust that an unfamiliar
    /// process is a NEW one, whose counter started at zero since the last look.
    package var started: Bool
    package var reset: AppUsageReset?

    package init(
        days: [AppDayUsage] = [],
        lastSeen: [String: ProcessBytes] = [:],
        started: Bool = false,
        reset: AppUsageReset? = nil
    ) {
        self.days = days
        self.lastSeen = lastSeen
        self.started = started
        self.reset = reset
    }
}

/// One program in the panel: what it is called, and what it used.
package struct AppUsageShare: Equatable, Sendable {
    package var name: String
    package var received: UInt64
    package var sent: UInt64

    package init(name: String, received: UInt64, sent: UInt64) {
        self.name = name
        self.received = received
        self.sent = sent
    }

    package var total: UInt64 { received &+ sent }
}

/// How a reading of the per-process counters becomes a day-by-day record.
///
/// Pure, so the checks pin the arithmetic rather than whatever this machine's
/// own processes happened to be doing.
package enum NetworkAppUsageMath {
    /// Kept in step with `NetworkUsageMath.historyLength`, so the breakdown
    /// reaches back exactly as far as the total it explains.
    package static let historyLength = NetworkUsageMath.historyLength

    /// How many programs a day remembers.
    ///
    /// The panel shows two. It keeps more than that because the day is still
    /// being written: the program in third place at noon may be first by six,
    /// and a record that only ever kept the leaders would have thrown away the
    /// evidence for that before it happened. Twelve is far more than the panel
    /// will ever ask for and still small enough that sixty-two days of it is a
    /// few tens of kilobytes.
    package static let appsPerDay = 12

    /// A ceiling on how many processes are remembered between readings, so a
    /// machine that churns through short-lived processes cannot grow this
    /// record without end. The busiest sample on a working Mac is a few dozen.
    package static let processLimit = 256

    /// How long a process that has stopped appearing is remembered for.
    ///
    /// Short, unlike an interface, because a process id is not a lasting name:
    /// it is handed back to the system and given to something else. Holding one
    /// for weeks would eventually meet a different program wearing it and
    /// subtract one's counter from the other's.
    package static let forgetProcessAfter: TimeInterval = 10 * 60

    /// The program a process belongs to.
    ///
    /// `nettop` names a process `<program>.<pid>`, and a program name may
    /// itself contain dots, so the split is at the LAST one. Anything that does
    /// not end in a number is not a process line and is refused.
    ///
    /// The name is tidied here rather than where it is drawn, because the
    /// tidying decides what adds up with what. A browser or an Electron app
    /// does its networking in child processes called "<name> Helper", and
    /// leaving the suffix on would list one program twice — once as itself and
    /// once as its helper — with its data split between the two rows and
    /// neither of them true. Removing a suffix from the name this Mac reports
    /// is not the same as looking the program up in a list of applications this
    /// app knows about; nothing here has to be taught about any program.
    ///
    /// Nothing else is invented. `nettop` truncates a long name to fifteen
    /// characters, so what comes back can be a stump like `AMPDeviceDiscov`,
    /// and it is shown as a stump: a guessed name on the row that exists to say
    /// which program used your data would be worse than a short one.
    package static func programName(fromKey key: String) -> String? {
        guard let dot = key.lastIndex(of: "."), dot != key.startIndex else { return nil }
        let pid = key[key.index(after: dot)...]
        guard !pid.isEmpty, pid.allSatisfy(\.isNumber) else { return nil }
        return tidied(String(key[key.startIndex..<dot]))
    }

    /// The helper suffixes a program's own child processes carry.
    ///
    /// Longest first, so "Claude Helper (Renderer)" loses the whole suffix
    /// rather than being cut back to "Claude Helper (Renderer" by a shorter
    /// match landing first.
    package static let helperSuffixes = [
        " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)", " Helper",
    ]

    package static func tidied(_ raw: String) -> String {
        for suffix in helperSuffixes where raw.hasSuffix(suffix) {
            let name = String(raw.dropLast(suffix.count))
            return name.isEmpty ? raw : name
        }
        return raw
    }

    /// How much of a process's counter is new since it was last read.
    ///
    /// Three cases, and the middle one is where this differs from the interface
    /// rule on purpose:
    /// - Nothing has ever been read: nothing. Every counter in that first
    ///   sample holds traffic from before anybody was watching.
    /// - Never seen before, but not the first sample: ALL of it. A process this
    ///   app has not met since its last look is one that started since, and a
    ///   process's counter starts at zero when the process does. The interface
    ///   rule says the opposite for exactly the same reason — an interface's
    ///   counter starts when the Mac boots, long before this app looks at it,
    ///   so its first value is history and a process's first value is not.
    /// - Grown: the difference, which is the ordinary case.
    /// - Shrunk: all of it. A process id can be handed back and given to
    ///   something else, and the something else starts at zero.
    package static func delta(previous: UInt64?, current: UInt64, hasStarted: Bool) -> UInt64 {
        guard hasStarted else { return 0 }
        guard let previous else { return current }
        return current >= previous ? current - previous : current
    }

    /// Folds one reading of the per-process counters into the ledger.
    package static func folded(
        _ ledger: AppUsageLedger,
        reading: [String: ProcessBytes],
        now: Date,
        calendar: Calendar = .current
    ) -> AppUsageLedger {
        var next = ledger

        var added: [String: AppBytes] = [:]
        for (key, bytes) in reading {
            guard let program = programName(fromKey: key) else { continue }
            let previous = ledger.lastSeen[key]

            // The same refusal the totals make, for the same reason: a reading
            // whose predecessor was taken on an earlier day, long enough ago
            // that the app was plainly not running in between, cannot be put
            // against any one day. See `NetworkUsageMath.maximumGapAcrossDays`.
            if let previous,
               !calendar.isDate(previous.seenAt, inSameDayAs: now),
               now.timeIntervalSince(previous.seenAt) > NetworkUsageMath.maximumGapAcrossDays {
                continue
            }

            let received = delta(
                previous: previous?.received, current: bytes.received, hasStarted: ledger.started)
            let sent = delta(
                previous: previous?.sent, current: bytes.sent, hasStarted: ledger.started)
            guard received > 0 || sent > 0 else { continue }
            var entry = added[program] ?? AppBytes()
            entry.received &+= received
            entry.sent &+= sent
            added[program] = entry
        }

        let day = calendar.startOfDay(for: now)
        var today = next.days.first(where: { $0.day == day }) ?? AppDayUsage(day: day)
        for (program, bytes) in added {
            var entry = today.apps[program] ?? AppBytes()
            entry.received &+= bytes.received
            entry.sent &+= bytes.sent
            today.apps[program] = entry
        }
        // Only the day being written is trimmed. Trimming every day on every
        // fold would keep re-sorting sixty-two dictionaries a minute to no
        // purpose — the older ones cannot change again.
        today.apps = trimmed(today.apps)
        if let index = next.days.firstIndex(where: { $0.day == day }) {
            next.days[index] = today
        } else {
            next.days.append(today)
        }

        next.days.sort { $0.day < $1.day }
        if next.days.count > historyLength {
            next.days.removeFirst(next.days.count - historyLength)
        }

        var seen = ledger.lastSeen
        for (key, bytes) in reading { seen[key] = bytes }
        seen = seen.filter { now.timeIntervalSince($0.value.seenAt) <= forgetProcessAfter }
        if seen.count > processLimit {
            let kept = seen.sorted { $0.value.seenAt > $1.value.seenAt }.prefix(processLimit)
            seen = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        next.lastSeen = seen
        next.started = true
        return next
    }

    /// Keeps the biggest few, so one day's record cannot grow without end.
    package static func trimmed(_ apps: [String: AppBytes]) -> [String: AppBytes] {
        guard apps.count > appsPerDay else { return apps }
        let kept = apps.sorted { left, right in
            left.value.total == right.value.total
                ? left.key < right.key
                : left.value.total > right.value.total
        }.prefix(appsPerDay)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// The programs that used the most over a span, biggest first.
    ///
    /// `from` is the start of the span — the same one the totals are summed
    /// over — or nil for a span with no fixed beginning.
    package static func topApps(
        _ ledger: AppUsageLedger,
        from: Date?,
        limit: Int,
        calendar: Calendar = .current
    ) -> [AppUsageShare] {
        let fromDay = from.map { calendar.startOfDay(for: $0) }
        var totals: [String: AppBytes] = [:]
        for entry in ledger.days where fromDay == nil || entry.day >= fromDay! {
            for (program, bytes) in entry.apps {
                var running = totals[program] ?? AppBytes()
                running.received &+= bytes.received
                running.sent &+= bytes.sent
                totals[program] = running
            }
        }

        // A reset part-way through a day: what that day already held is not
        // part of "since you reset it". Mirrors the totals exactly.
        if let reset = ledger.reset, let fromDay,
           calendar.startOfDay(for: reset.at) >= fromDay {
            for (program, before) in reset.dayApps {
                guard var running = totals[program] else { continue }
                running.received = running.received > before.received
                    ? running.received - before.received : 0
                running.sent = running.sent > before.sent ? running.sent - before.sent : 0
                totals[program] = running
            }
        }

        var shares: [AppUsageShare] = []
        for (program, bytes) in totals where bytes.total > 0 {
            shares.append(
                AppUsageShare(name: program, received: bytes.received, sent: bytes.sent))
        }
        // Biggest first, and ties broken by name so the order cannot flicker
        // between two draws of the same numbers.
        shares.sort { left, right in
            left.total == right.total ? left.name < right.name : left.total > right.total
        }
        return Array(shares.prefix(limit))
    }

    /// Starts the breakdown again, without disturbing the day-by-day record the
    /// other two spans read from.
    package static func afterReset(
        _ ledger: AppUsageLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> AppUsageLedger {
        var next = ledger
        let day = calendar.startOfDay(for: now)
        let today = next.days.first(where: { $0.day == day })?.apps ?? [:]
        next.reset = AppUsageReset(at: now, dayApps: today)
        return next
    }
}

/// Where the breakdown is kept between launches: beside the totals, in the
/// app's own preferences, so the promise that this app writes no files holds.
package enum NetworkAppUsageStore {
    package static let key = "hashnotch.network.apps.v1"

    package static func load(from defaults: UserDefaults) -> AppUsageLedger? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppUsageLedger.self, from: data)
    }

    package static func save(_ ledger: AppUsageLedger, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }

    package static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
