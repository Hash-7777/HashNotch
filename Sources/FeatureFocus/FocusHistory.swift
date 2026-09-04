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

    /// Read leniently. A history that will not decode must not silently become
    /// an empty one that the next save then writes over the top of the real
    /// thing — losing a week of somebody's days without a word.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([FocusTally].self, forKey: .days) ?? []
    }

    /// How many days the sentence talks about, today included.
    public static let daysCounted = 7

    /// How many FINISHED days are kept, which is one fewer.
    ///
    /// Seven kept plus today is eight, and the sentence said seven. Off by a
    /// day, every day, in the direction that flatters — which is the worst
    /// direction for a number somebody is meant to trust.
    public static let keptDays = daysCounted - 1

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

    /// The days that are actually inside the window, today excluded.
    ///
    /// Filtered by the CALENDAR rather than by how many are stored. Somebody who
    /// focused for a week, then did not touch the Mac for a month, still had
    /// seven days on disk — and the sentence went on reporting them as "the last
    /// 7 days" a month after they happened. Stored is not the same as recent,
    /// and only one of the two is what the sentence claims.
    public static func recentDays(
        _ history: FocusHistory,
        now: Date,
        calendar: Calendar = .current
    ) -> [FocusTally] {
        let today = FocusTallyMath.day(of: now, calendar: calendar)
        // Counted in days rather than in seconds, so an hour lost or gained to
        // daylight saving cannot push a day out of the window.
        guard let earliest = calendar.date(
            byAdding: .day, value: -(FocusHistory.daysCounted - 1), to: today
        ) else { return history.days }
        return history.days.filter { $0.day >= earliest && $0.day < today }
    }

    /// Everything focused in the window, today included.
    public static func weekSeconds(
        _ history: FocusHistory,
        today: FocusTally,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimeInterval {
        recentDays(history, now: now, calendar: calendar)
            .reduce(today.workSeconds) { $0 + $1.workSeconds }
    }

    /// The one line under the cycle.
    ///
    /// A week rather than a day, and a total rather than an average. An average
    /// invites a comparison, and a comparison against a part-finished day
    /// flatters somebody at six in the evening and scolds them at ten in the
    /// morning with the same number.
    ///
    /// It states the figure and stops. It said "Keep it up", which is the app
    /// having an opinion about how somebody's week is going — and a readout that
    /// congratulates you is one you stop believing when it congratulates you on
    /// a bad week too.
    ///
    /// It says "focused" so the figure is never a bare number, and it says the
    /// stretch so it is never mistaken for a total of all time. There is no
    /// vocabulary in it to learn.
    public static func weekText(
        _ history: FocusHistory,
        today: FocusTally,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let seconds = weekSeconds(history, today: today, now: now, calendar: calendar)
        guard seconds >= 60 else { return "No focus time in the last 7 days." }
        return "You focused \(FocusTallyMath.duration(seconds)) in the last 7 days."
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
