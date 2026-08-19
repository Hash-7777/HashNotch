import Foundation
import HashNotchKit

/// How much has gone through the network, kept as a day-by-day record.
///
/// The kernel counts bytes per interface since that interface came up, and
/// those counters are the only source of this figure — nothing here watches
/// traffic, and no packet, address or name is read. A counter is a number that
/// grows; what somebody wants to know is how much of it belongs to today, or to
/// this month, and that is a question the counters cannot answer on their own.
///
/// So this keeps a ledger of daily totals, built by taking the difference
/// between one reading and the next. Every span the panel offers — today, this
/// month, since you last reset it — is a sum over that one ledger, which is why
/// changing the span shows a different slice of what is already known instead
/// of starting again from zero.

/// One day's bytes.
package struct DayUsage: Codable, Equatable, Sendable {
    /// The start of the day these figures belong to, in the local calendar.
    package var day: Date
    package var received: UInt64
    package var sent: UInt64

    package init(day: Date, received: UInt64 = 0, sent: UInt64 = 0) {
        self.day = day
        self.received = received
        self.sent = sent
    }
}

/// What one interface's counters read when they were last looked at.
package struct InterfaceBytes: Codable, Equatable, Sendable {
    package var received: UInt64
    package var sent: UInt64
    package var seenAt: Date

    package init(received: UInt64, sent: UInt64, seenAt: Date) {
        self.received = received
        self.sent = sent
        self.seenAt = seenAt
    }
}

/// The mark left behind when somebody starts the count again.
///
/// A reset in the middle of a day cannot simply throw the day away — the other
/// two spans are counted from the same record and have every right to it — so
/// what the day already held is remembered here and taken off the total.
package struct UsageReset: Codable, Equatable, Sendable {
    package var at: Date
    package var dayReceived: UInt64
    package var daySent: UInt64

    package init(at: Date, dayReceived: UInt64, daySent: UInt64) {
        self.at = at
        self.dayReceived = dayReceived
        self.daySent = daySent
    }
}

/// The whole record: the days, and where each interface's counters had got to.
package struct NetworkUsageLedger: Codable, Equatable, Sendable {
    package var days: [DayUsage]
    package var lastSeen: [String: InterfaceBytes]
    /// The first moment anything was counted, so the panel can say when a
    /// figure covers less than the span it is named after.
    package var countingSince: Date?
    package var reset: UsageReset?

    package init(
        days: [DayUsage] = [],
        lastSeen: [String: InterfaceBytes] = [:],
        countingSince: Date? = nil,
        reset: UsageReset? = nil
    ) {
        self.days = days
        self.lastSeen = lastSeen
        self.countingSince = countingSince
        self.reset = reset
    }
}

/// A figure for one span, and how much of that span it really covers.
package struct NetworkUsageTotals: Equatable, Sendable {
    package var received: UInt64
    package var sent: UInt64
    /// The earliest moment these figures actually account for. Later than the
    /// start of the span when the app was not there for the whole of it.
    package var countedSince: Date?
    /// Whether the figures cover the span from its beginning. False the first
    /// day of use, and for a month that began before the app was installed —
    /// the moment a total would otherwise quietly understate itself.
    package var coversWholeSpan: Bool

    package init(
        received: UInt64 = 0,
        sent: UInt64 = 0,
        countedSince: Date? = nil,
        coversWholeSpan: Bool = true
    ) {
        self.received = received
        self.sent = sent
        self.countedSince = countedSince
        self.coversWholeSpan = coversWholeSpan
    }
}

/// Which interfaces count as data used, and how a reading becomes a total.
///
/// Everything here is pure so the checks can pin the arithmetic rather than
/// pinning whatever the machine's own counters happened to say.
package enum NetworkUsageMath {
    /// How many days of history are kept: two months, so "this month" is whole
    /// on its first day and a reset a few weeks back still has its days.
    package static let historyLength = 62

    /// How long an interface that has stopped appearing is remembered for.
    /// It is remembered at all so that one which comes back — a dock unplugged
    /// over a weekend — is recognised as having restarted its counters rather
    /// than being met as a stranger.
    package static let forgetInterfaceAfter: TimeInterval = 30 * 24 * 60 * 60

    /// A ceiling on how many interfaces are remembered, so a machine that
    /// invents new interface names cannot grow this record without end.
    package static let interfaceLimit = 32

    /// Whether an interface's bytes are data used.
    ///
    /// The rule is a list of what to leave out rather than a list of what to
    /// take, so an unfamiliar interface is counted rather than silently
    /// ignored — a figure that is too high is visible and can be reported, and
    /// one that is too low looks exactly like a quiet day.
    ///
    /// What is left out, and why:
    /// - `lo` is the machine talking to itself and never leaves it.
    /// - `utun`, `ipsec`, `ppp`, `gif`, `stf`, `tun`, `tap` carry traffic that
    ///   also goes over the real link underneath. Counting both would report a
    ///   VPN's every byte twice.
    /// - `awdl`, `llw` are AirDrop and its neighbours: Mac to Mac, no internet.
    /// - `bridge`, `vmenet`, `vnic`, `ap` are bridges, virtual machines and
    ///   sharing this Mac's connection — all of them the same bytes again,
    ///   counted a second time on their way past.
    /// - `anpi` is an internal link between this Mac's own processors.
    package static func counts(_ name: String) -> Bool {
        let ignored = [
            "lo",
            "utun", "ipsec", "ppp", "gif", "stf", "tun", "tap",
            "awdl", "llw",
            "bridge", "vmenet", "vnic", "ap",
            "anpi",
        ]
        return !ignored.contains { name.hasPrefix($0) }
    }

    /// How much of a counter's current value is new since it was last read.
    ///
    /// Three cases, and the middle one is the whole reason this is a function:
    /// - Never seen before: nothing. The counter holds traffic from before
    ///   anybody was watching — most of it from before the app was installed —
    ///   and counting it as today's would report a fresh install as having used
    ///   several gigabytes in its first second.
    /// - Grown: the difference, which is the ordinary case.
    /// - Shrunk: all of it. A counter only goes backwards by starting again —
    ///   the interface went down, or the Mac was restarted — so what it holds
    ///   now is exactly what has gone through since it did.
    package static func delta(previous: UInt64?, current: UInt64) -> UInt64 {
        guard let previous else { return 0 }
        return current >= previous ? current - previous : current
    }

    /// Folds one reading of the counters into the ledger.
    ///
    /// Takes no notion of which span is being displayed: the record is kept by
    /// day whatever the panel is showing, so changing that setting costs
    /// nothing and loses nothing.
    package static func folded(
        _ ledger: NetworkUsageLedger,
        reading: [String: InterfaceBytes],
        now: Date,
        calendar: Calendar = .current
    ) -> NetworkUsageLedger {
        var next = ledger
        next.countingSince = ledger.countingSince ?? now

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, bytes) in reading {
            let previous = ledger.lastSeen[name]
            received &+= delta(previous: previous?.received, current: bytes.received)
            sent &+= delta(previous: previous?.sent, current: bytes.sent)
        }

        let day = calendar.startOfDay(for: now)
        if let index = next.days.firstIndex(where: { $0.day == day }) {
            next.days[index].received &+= received
            next.days[index].sent &+= sent
        } else {
            next.days.append(DayUsage(day: day, received: received, sent: sent))
        }
        next.days.sort { $0.day < $1.day }
        if next.days.count > historyLength {
            next.days.removeFirst(next.days.count - historyLength)
        }

        // An interface missing from this reading keeps its remembered value, so
        // that its counters restarting while it was away is still noticed. It
        // is dropped only once it has been gone long enough to be gone.
        var seen = ledger.lastSeen
        for (name, bytes) in reading { seen[name] = bytes }
        seen = seen.filter { now.timeIntervalSince($0.value.seenAt) <= forgetInterfaceAfter }
        if seen.count > interfaceLimit {
            let kept = seen.sorted { $0.value.seenAt > $1.value.seenAt }.prefix(interfaceLimit)
            seen = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        next.lastSeen = seen

        return next
    }

    /// The start of the span being asked about, or nil for one that has no
    /// fixed beginning — a count that has never been reset begins wherever the
    /// record does.
    package static func spanStart(
        _ period: NetworkUsagePeriod,
        ledger: NetworkUsageLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch period {
        case .today:
            return calendar.startOfDay(for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
        case .sinceReset:
            return ledger.reset?.at ?? ledger.countingSince
        }
    }

    /// The figures for one span.
    package static func totals(
        _ ledger: NetworkUsageLedger,
        period: NetworkUsagePeriod,
        now: Date,
        calendar: Calendar = .current
    ) -> NetworkUsageTotals {
        let start = spanStart(period, ledger: ledger, now: now, calendar: calendar)
        guard let start else {
            return NetworkUsageTotals(countedSince: ledger.countingSince, coversWholeSpan: true)
        }

        let fromDay = calendar.startOfDay(for: start)
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for entry in ledger.days where entry.day >= fromDay {
            received &+= entry.received
            sent &+= entry.sent
        }

        // A reset part-way through a day: the bytes that day already held are
        // not part of "since you reset it". Subtracted rather than forgotten,
        // because the day itself still belongs to today and to this month.
        if period == .sinceReset, let reset = ledger.reset,
           calendar.startOfDay(for: reset.at) >= fromDay {
            received = received > reset.dayReceived ? received - reset.dayReceived : 0
            sent = sent > reset.daySent ? sent - reset.daySent : 0
        }

        // What is really covered: the later of when counting began and the
        // oldest day still kept, since a day that has been pruned is a day this
        // total cannot include.
        var countedSince = ledger.countingSince ?? start
        if let oldest = ledger.days.first?.day, oldest > countedSince {
            countedSince = oldest
        }
        if period == .sinceReset, let reset = ledger.reset, reset.at > countedSince {
            countedSince = reset.at
        }
        let covers = countedSince <= start
        return NetworkUsageTotals(
            received: received,
            sent: sent,
            countedSince: covers ? start : countedSince,
            coversWholeSpan: covers
        )
    }

    /// Starts the count again, without disturbing the day-by-day record the
    /// other two spans are read from.
    package static func afterReset(
        _ ledger: NetworkUsageLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> NetworkUsageLedger {
        var next = ledger
        let day = calendar.startOfDay(for: now)
        let today = ledger.days.first { $0.day == day }
        next.reset = UsageReset(
            at: now,
            dayReceived: today?.received ?? 0,
            daySent: today?.sent ?? 0
        )
        return next
    }
}

/// Reads the kernel's per-interface byte counters.
package enum NetworkInterfaces {
    /// Every interface whose bytes count as data used, with what its counters
    /// currently read. Public API only: `getifaddrs`, the same call the speed
    /// readout has always used.
    package static func read(now: Date = Date()) -> [String: InterfaceBytes] {
        var result: [String: InterfaceBytes] = [:]

        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return result }
        defer { freeifaddrs(addrs) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let sockaddr = interface.ifa_addr,
               sockaddr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if NetworkUsageMath.counts(name), let data = interface.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    result[name] = InterfaceBytes(
                        received: UInt64(stats.ifi_ibytes),
                        sent: UInt64(stats.ifi_obytes),
                        seenAt: now
                    )
                }
            }
            cursor = interface.ifa_next
        }
        return result
    }

    /// The same reading summed, which is what a speed is measured from.
    package static func totalBytes(_ reading: [String: InterfaceBytes]) -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for bytes in reading.values {
            received &+= bytes.received
            sent &+= bytes.sent
        }
        return (received, sent)
    }
}

/// Where the ledger is kept between launches.
///
/// `UserDefaults`, like the token count's cache and for the same reason: the app
/// promises in SECURITY.md that it writes no files, and a record of bytes-per-day
/// belongs inside that promise rather than beside it. What is stored is a few
/// numbers a day and the names of this Mac's own network interfaces — no
/// address, no site, nothing about where any of it went.
package enum NetworkUsageStore {
    private static let key = "hashnotch.network.usage.v1"

    package static func load(from defaults: UserDefaults = .standard) -> NetworkUsageLedger? {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(NetworkUsageLedger.self, from: data)
        else { return nil }
        return ledger
    }

    package static func save(_ ledger: NetworkUsageLedger, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }

    /// Package-visible so the checks can work in an isolated suite without
    /// touching the real preferences.
    package static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
