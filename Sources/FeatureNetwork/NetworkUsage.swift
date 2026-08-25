import Foundation
import Darwin
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
    /// Whether some of this day went by uncounted — the app was not running
    /// across a stretch of it that could not be attributed to one day.
    ///
    /// Optional so a record written before this existed still decodes; absent
    /// means the day is whole.
    package var partial: Bool?

    package var isPartial: Bool { partial == true }

    package init(day: Date, received: UInt64 = 0, sent: UInt64 = 0, partial: Bool? = nil) {
        self.day = day
        self.received = received
        self.sent = sent
        self.partial = partial
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
    /// Whether a stretch INSIDE the span went by uncounted: the app was not
    /// running across days, so what happened in between could not be put
    /// against any one of them and was not counted at all.
    ///
    /// Separate from `coversWholeSpan`, because they are different admissions.
    /// One says the count started late; this says there is a hole in the
    /// middle of it.
    package var missedTime: Bool

    package init(
        received: UInt64 = 0,
        sent: UInt64 = 0,
        countedSince: Date? = nil,
        coversWholeSpan: Bool = true,
        missedTime: Bool = false
    ) {
        self.received = received
        self.sent = sent
        self.countedSince = countedSince
        self.coversWholeSpan = coversWholeSpan
        self.missedTime = missedTime
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

    /// How long a gap between two readings may be, when it crosses midnight,
    /// before what happened in it is refused rather than guessed at.
    ///
    /// The counters keep running while the app is not, so reopening it always
    /// finds bytes that arrived in between. Which day those belong to is the
    /// whole question. Quit at nine and reopen at five the same day and the
    /// answer is not in doubt: it was all today, and counting it is what makes
    /// "used today" true rather than "used while the app happened to be open".
    ///
    /// Quit on Friday and reopen on Monday and there is no answer. The bytes
    /// are real and they are spread across three days in proportions nothing
    /// on this Mac records. Putting them on Monday would invent the busiest day
    /// of the month out of a weekend, so they are refused, the counters are
    /// taken as a new starting point, and the days involved are marked as
    /// having gone by uncounted — which the panel then says out loud.
    ///
    /// Five minutes, so that the ordinary tick across midnight — the app
    /// running the whole time, one reading at 23:59 and the next at 00:00 —
    /// stays an ordinary reading and lands on the new day. At most that
    /// misplaces a few seconds of traffic; refusing it would throw away the
    /// same seconds and call the day incomplete, which is worse for being
    /// louder.
    package static let maximumGapAcrossDays: TimeInterval = 5 * 60

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

        // A reading whose predecessor was taken on an earlier day, long enough
        // ago that the app was plainly not running in between, cannot be
        // attributed. See `maximumGapAcrossDays`.
        var refused = false
        var earliestRefused: Date?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, bytes) in reading {
            let previous = ledger.lastSeen[name]
            if let previous,
               !calendar.isDate(previous.seenAt, inSameDayAs: now),
               now.timeIntervalSince(previous.seenAt) > maximumGapAcrossDays {
                refused = true
                if earliestRefused == nil || previous.seenAt < earliestRefused! {
                    earliestRefused = previous.seenAt
                }
                continue
            }
            received &+= delta(previous: previous?.received, current: bytes.received)
            sent &+= delta(previous: previous?.sent, current: bytes.sent)
        }

        let day = calendar.startOfDay(for: now)
        if let index = next.days.firstIndex(where: { $0.day == day }) {
            next.days[index].received &+= received
            next.days[index].sent &+= sent
            if refused { next.days[index].partial = true }
        } else {
            next.days.append(DayUsage(day: day, received: received, sent: sent, partial: refused ? true : nil))
        }

        // The days the app was away for are marked too, so a month containing
        // them does not read as though nothing happened on them.
        if refused, let from = earliestRefused {
            var marked = calendar.startOfDay(for: from)
            let today = calendar.startOfDay(for: now)
            var guard_ = 0
            while marked < today, guard_ < historyLength {
                if let index = next.days.firstIndex(where: { $0.day == marked }) {
                    next.days[index].partial = true
                } else {
                    next.days.append(DayUsage(day: marked, partial: true))
                }
                guard let step = calendar.date(byAdding: .day, value: 1, to: marked) else { break }
                marked = step
                guard_ += 1
            }
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
        // A hole in the middle of the span: days the app was away for across
        // midnight, whose traffic could not be put against any one day.
        let missed = ledger.days.contains { $0.day >= fromDay && $0.isPartial }
        return NetworkUsageTotals(
            received: received,
            sent: sent,
            countedSince: covers ? start : countedSince,
            coversWholeSpan: covers,
            missedTime: missed
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
    /// currently read.
    ///
    /// Read through `sysctl(NET_RT_IFLIST2)`, which hands back `if_data64`,
    /// and NOT through `getifaddrs`, which was the obvious call and is the
    /// wrong one. `getifaddrs` fills in a plain `if_data`, whose `ifi_ibytes`
    /// and `ifi_obytes` are **32 bits wide** — measured on this Mac, four bytes
    /// each. They therefore roll over every 4.29 GB, which an evening of video
    /// passes, and a counter that has rolled over looks exactly like one that
    /// restarted: it went backwards. The day's total would then quietly lose
    /// everything between the last reading and the ceiling — up to 4 GB at a
    /// time, with nothing on screen to say so.
    ///
    /// `if_data64` carries the same fields at 64 bits, where the ceiling is 16
    /// exabytes and a rollover is not a thing that happens. It is the same
    /// source `netstat -ib` reads, which is what makes the two comparable.
    ///
    /// There is no fallback to the 32-bit call on purpose. If this fails there
    /// is no reading, and the panel says nothing — which is the right answer,
    /// because the alternative is a figure that is wrong in a way nobody can
    /// see.
    package static func read(now: Date = Date()) -> [String: InterfaceBytes] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return [:] }

        var result: [String: InterfaceBytes] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            // The buffer is a run of variable-length messages, so each one is
            // read at whatever offset the last finished at — never assume the
            // alignment a struct would normally get.
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0, offset + length <= size else { break }
                defer { offset += length }
                guard header.ifm_type == RTM_IFINFO2 else { continue }

                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                // The interface's name follows the header as a link-layer
                // address, whose own length field says how much of it is the
                // name. Nothing here is null-terminated.
                let linkOffset = offset + MemoryLayout<if_msghdr2>.size
                guard linkOffset + MemoryLayout<sockaddr_dl>.size <= size else { continue }
                let link = raw.loadUnaligned(fromByteOffset: linkOffset, as: sockaddr_dl.self)
                let nameLength = Int(link.sdl_nlen)
                guard nameLength > 0 else { continue }
                // Asked for rather than assumed. `offset(of:)` answers nil for
                // a field it cannot address directly, and this one is a C
                // tuple whose import is Swift's business rather than ours — so
                // a force unwrap here is a bet that the compiler will keep
                // importing a system header the same way for ever, settled by
                // crashing. It runs once a second on every Mac this ships to.
                // Skipping an interface it cannot name is the whole cost of
                // being wrong.
                guard let dataOffset = MemoryLayout.offset(of: \sockaddr_dl.sdl_data)
                else { continue }
                let nameOffset = linkOffset + dataOffset
                guard nameOffset + nameLength <= size else { continue }
                let name = String(decoding: raw[nameOffset..<(nameOffset + nameLength)], as: UTF8.self)

                guard NetworkUsageMath.counts(name) else { continue }
                result[name] = InterfaceBytes(
                    received: message.ifm_data.ifi_ibytes,
                    sent: message.ifm_data.ifi_obytes,
                    seenAt: now
                )
            }
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
    /// Package-visible so a check can put a document written by an older build
    /// under it and prove it still loads. What it guards against is quiet: this
    /// store answers nil for anything it cannot decode and the caller starts a
    /// fresh ledger, so a change to the stored shape does not fail loudly — it
    /// empties somebody's running totals without a word.
    package static let key = "hashnotch.network.usage.v1"

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
