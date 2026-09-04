import Foundation

/// The last few days, so the one line under the cycle has something to add up.
///
/// A single day's figure is not worth reading — three hours twenty is good or
/// bad only against something, and a day on its own has nothing to be measured
/// by. A week has enough in it to be worth a sentence.
///
/// It is a week on purpose. Long enough to mean something, short enough that it
/// is not a record of somebody's working life sitting on a disk, and one press
/// in the settings page deletes it. What it holds is a date and two numbers per
/// day — never what anybody was working on, which this app has no way of
/// knowing and no business asking.
public struct FocusHistory: Codable, Equatable, Sendable {
    /// Finished days, most recent first.
    public var days: [FocusTally]

    public init(days: [FocusTally] = []) {
        self.days = days
    }

    /// How many are kept.
    public static let keptDays = 7

    public var isEmpty: Bool { days.isEmpty }
}

/// The arithmetic, pure, because a week cannot be lived through inside a check.
public enum FocusHistoryMath {
    /// Put a finished day away, newest first, and drop anything past the limit.
    ///
    /// A day with nothing in it is not kept: a weekend, or a day the Mac was
    /// off, is not a day somebody sat there achieving nothing.
    public static func archiving(_ history: FocusHistory, finished: FocusTally) -> FocusHistory {
        guard !finished.isEmpty else { return history }
        var days = history.days.filter { $0.day != finished.day }
        days.insert(finished, at: 0)
        return FocusHistory(days: Array(days.prefix(FocusHistory.keptDays)))
    }

    /// Everything focused in the last week, today included.
    public static func weekSeconds(_ history: FocusHistory, today: FocusTally) -> TimeInterval {
        history.days.reduce(today.workSeconds) { $0 + $1.workSeconds }
    }

    /// The one line under the cycle.
    ///
    /// A week rather than a day, and a total rather than an average, because
    /// both of those are things somebody can feel good about. An average invites
    /// a comparison, and a comparison against a part-finished day flatters
    /// somebody at six in the evening and scolds them at ten in the morning with
    /// the same number.
    ///
    /// It says "focused" so the figure is never a bare number, and it says the
    /// stretch so it is never mistaken for a total of all time. There is no
    /// vocabulary in it to learn: no rounds, no blocks, no marks to interpret.
    public static func weekText(_ history: FocusHistory, today: FocusTally) -> String {
        let seconds = weekSeconds(history, today: today)
        guard seconds >= 60 else {
            return "No focus time in the last 7 days yet. Start when you are ready."
        }
        return "You focused \(FocusTallyMath.duration(seconds)) in the last 7 days. Keep it up."
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
