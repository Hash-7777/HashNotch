import Foundation

/// What today came to.
///
/// The point of it is that it does not flatter you. Time counted as focus is
/// time a piece of work was running AND somebody was at the Mac; the moment the
/// screen goes away that stops, and what was running is recorded as abandoned
/// rather than quietly completed. A tally that counted a locked Mac as focus
/// would be a wish with a number beside it.
public struct FocusTally: Codable, Equatable, Sendable {
    /// The day this belongs to, as the start of that day in the local calendar.
    public var day: Date
    public var workSeconds: TimeInterval
    public var breakSeconds: TimeInterval
    /// Time the screen was away while a piece of work was running. Kept apart
    /// from work rather than subtracted into it, because "you were gone for
    /// forty minutes" is the more useful of the two facts.
    public var awaySeconds: TimeInterval
    /// Pieces of work carried all the way to their end.
    public var finishedWork: Int
    /// Pieces of work that ended some other way — cancelled, or walked out of.
    public var abandonedWork: Int

    public init(
        day: Date,
        workSeconds: TimeInterval = 0,
        breakSeconds: TimeInterval = 0,
        awaySeconds: TimeInterval = 0,
        finishedWork: Int = 0,
        abandonedWork: Int = 0
    ) {
        self.day = day
        self.workSeconds = workSeconds
        self.breakSeconds = breakSeconds
        self.awaySeconds = awaySeconds
        self.finishedWork = finishedWork
        self.abandonedWork = abandonedWork
    }

    public var isEmpty: Bool {
        workSeconds < 1 && breakSeconds < 1 && awaySeconds < 1
            && finishedWork == 0 && abandonedWork == 0
    }
}

/// The arithmetic behind the tally, kept pure. None of it can be exercised by
/// living through a day.
public enum FocusTallyMath {
    /// The day a moment belongs to, in the calendar the person is actually in.
    public static func day(of moment: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: moment)
    }

    /// The tally to use now: the one that was kept if it is still today's, and
    /// a fresh one if the day has turned over.
    ///
    /// Rolled over rather than added to, because a Mac left running through
    /// midnight would otherwise show one number covering two days and no way to
    /// tell that is what it was.
    public static func current(
        _ kept: FocusTally?,
        now: Date,
        calendar: Calendar = .current
    ) -> FocusTally {
        let today = day(of: now, calendar: calendar)
        guard let kept, kept.day == today else { return FocusTally(day: today) }
        return kept
    }

    /// A finished piece of work, or a break, added to the day.
    public static func adding(
        _ tally: FocusTally,
        block: FocusBlock,
        seconds: TimeInterval,
        completed: Bool
    ) -> FocusTally {
        var next = tally
        let worked = max(0, seconds)
        if block.isWork {
            next.workSeconds += worked
            if completed { next.finishedWork += 1 } else { next.abandonedWork += 1 }
        } else {
            next.breakSeconds += worked
        }
        return next
    }

    /// Time the screen was away while something was running.
    public static func addingAway(_ tally: FocusTally, seconds: TimeInterval) -> FocusTally {
        var next = tally
        next.awaySeconds += max(0, seconds)
        return next
    }

    /// What the day's figures are CALLED.
    ///
    /// Kept as rules rather than written into the view, because the wording has
    /// been wrong twice and both times for the same reason: a number was shown
    /// without the noun that says what it counts. "1 hr 15 min" of what. "3"
    /// of what. Short is not the goal — a reader who has to guess has been given
    /// nothing, however few words it took.
    ///
    /// The word is "round", because that is the word the settings page already
    /// uses. "Block" was this file's own coinage and appeared nowhere a person
    /// would have met it.
    public static func focusedText(_ seconds: TimeInterval) -> String {
        "\(duration(seconds)) focused"
    }

    public static func roundsText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "round" : "rounds") done"
    }

    public static func stoppedText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "round" : "rounds") stopped early"
    }

    /// How long something lasted, in the fewest words that are still true.
    ///
    /// Hours and minutes, and never "0 hr 20 min" — a leading zero hour is a
    /// word that carries nothing.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

}
