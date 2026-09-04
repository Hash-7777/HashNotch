import Foundation

/// The days behind today.
///
/// Today's figure on its own is not information. "Three hours twenty" is good or
/// bad only against something, and the first version of this kept nothing — so
/// the tally could never acquire the one thing that would have made it worth
/// reading. A handful of days fixes that and costs a few hundred bytes.
///
/// It is a handful on purpose. Enough to know what an ordinary day looks like,
/// short enough that it is not a record of your working life sitting on a disk,
/// and it can be cleared from the settings page in one press. What it holds is
/// four numbers and a date per day — never what you were working on, which this
/// app has no way of knowing and no business asking.
public struct FocusHistory: Codable, Equatable, Sendable {
    /// Finished days, most recent first.
    public var days: [FocusTally]

    public init(days: [FocusTally] = []) {
        self.days = days
    }

    /// How many are kept. A working week, so the average is not thrown by one
    /// unusual day and not stretched over a month of them.
    public static let keptDays = 7

    public var isEmpty: Bool { days.isEmpty }
}

/// The arithmetic, pure, because a week cannot be lived through inside a check.
public enum FocusHistoryMath {
    /// Put a finished day away, newest first, and drop anything past the limit.
    ///
    /// A day with nothing in it is not kept: a weekend, or a day the Mac was
    /// off, would otherwise drag the average down as though somebody had sat
    /// there achieving nothing.
    public static func archiving(_ history: FocusHistory, finished: FocusTally) -> FocusHistory {
        guard !finished.isEmpty else { return history }
        var days = history.days.filter { $0.day != finished.day }
        days.insert(finished, at: 0)
        return FocusHistory(days: Array(days.prefix(FocusHistory.keptDays)))
    }

    /// The average focus on the days kept, or nil when there are none.
    public static func averageWorkSeconds(_ history: FocusHistory) -> TimeInterval? {
        let worked = history.days.filter { $0.workSeconds >= 60 }
        guard !worked.isEmpty else { return nil }
        return worked.reduce(0) { $0 + $1.workSeconds } / Double(worked.count)
    }

    /// What an ordinary day looks like, or nothing when there is nothing honest
    /// to say.
    ///
    /// Three words and a number. It said "1 hr 50 min on an average day, over 6
    /// days", which is two clauses and a tail explaining the sample size to
    /// somebody who did not ask.
    ///
    /// Still a fact and never a verdict. Putting a part-finished day against
    /// whole ones would flatter somebody at six in the evening and scold them
    /// at ten in the morning, with the same number doing both — which is how a
    /// figure like this stops being trusted. "Usually" says what is normal for
    /// them and leaves the comparing to the person, who can do it and this
    /// cannot.
    public static func averageText(_ history: FocusHistory) -> String? {
        guard let average = averageWorkSeconds(history) else { return nil }
        return "Usually \(FocusTallyMath.duration(average)) a day"
    }

}

/// Where the days behind today are kept.
package enum FocusHistoryStore {
    package static let key = "hashnotch.focus.history.v1"

    package static func load(from defaults: UserDefaults) -> FocusHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(FocusHistory.self, from: data)
        else { return FocusHistory() }
        return history
    }

    package static func save(_ history: FocusHistory, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    package static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
