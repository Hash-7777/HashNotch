import Foundation

/// What one day came to.
///
/// Two figures, and only two. It used to keep four — rest, time away, and rounds
/// given up on — none of which was ever shown once the panel was rebuilt around
/// a single sentence. A number written and never read is not a record, it is
/// something about somebody kept for no reason, which is the last thing this app
/// should be doing.
///
/// The honesty is in the engine rather than in a column: time only accrues while
/// somebody is actually at the Mac, and a round they walked out of ends where
/// they left and never counts as finished. Dropping the counters changed what is
/// stored, not what is true.
public struct FocusTally: Codable, Equatable, Sendable {
    /// The day this belongs to, as the start of that day in the local calendar.
    public var day: Date
    public var workSeconds: TimeInterval
    /// Rounds carried all the way to their end. Kept because the cycle needs it
    /// — it is what decides when the long rest is due — not to be displayed.
    public var finishedWork: Int

    public init(day: Date, workSeconds: TimeInterval = 0, finishedWork: Int = 0) {
        self.day = day
        self.workSeconds = workSeconds
        self.finishedWork = finishedWork
    }

    /// Read leniently, so a day written by an earlier build — which kept more —
    /// still loads instead of being thrown away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Date.self, forKey: .day)
        workSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .workSeconds) ?? 0
        finishedWork = try container.decodeIfPresent(Int.self, forKey: .finishedWork) ?? 0
    }

    public var isEmpty: Bool { workSeconds < 1 && finishedWork == 0 }
}

/// The arithmetic behind a day, kept pure.
public enum FocusTallyMath {
    /// The day a moment belongs to, in the calendar the person is actually in.
    public static func day(of moment: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: moment)
    }

    /// The tally to use now: the one that was kept if it is still today's, and a
    /// fresh one if the day has turned over.
    public static func current(
        _ kept: FocusTally?,
        now: Date,
        calendar: Calendar = .current
    ) -> FocusTally {
        let today = day(of: now, calendar: calendar)
        guard let kept, kept.day == today else { return FocusTally(day: today) }
        return kept
    }

    /// A round that ended, added to the day.
    ///
    /// A rest adds nothing at all. It is not work, and it is not a thing anybody
    /// needs counted for them.
    public static func adding(
        _ tally: FocusTally,
        block: FocusBlock,
        seconds: TimeInterval,
        completed: Bool
    ) -> FocusTally {
        guard block.isWork else { return tally }
        var next = tally
        next.workSeconds += max(0, seconds)
        if completed { next.finishedWork += 1 }
        return next
    }

    /// How long something lasted, in the fewest words that are still true.
    /// Never "0 hr 20 min" — a leading zero hour is a word carrying nothing.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
