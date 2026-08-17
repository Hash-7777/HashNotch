import Foundation

/// The last totals counted, remembered so the panel opens on a number.
///
/// Counting a day's tokens means reading every transcript the day has touched,
/// and the first pass after launch has no remembered read positions to shorten
/// it. Without this the row showed a confident zero for as long as that took,
/// which is worse than showing nothing: a zero is an answer, and it was the
/// wrong one.
///
/// Written to `UserDefaults`, deliberately, rather than to a cache file. The app
/// promises in SECURITY.md that it writes no files at all and that its only
/// persistent state is its own settings; a few integers and a date belong inside
/// that promise rather than beside it.
///
/// The day is stored with the totals because they are only ever true of one day.
/// A cache from yesterday is not a stale number to be corrected, it is a
/// different question's answer, and it is discarded rather than shown.
package enum TokenTotalsCache {
    private static let key = "hashnotch.tokens.today.v1"

    package struct Entry: Codable, Equatable {
        package var day: Date
        package var totals: TokenTotals
        package var countedAt: Date

        package init(day: Date, totals: TokenTotals, countedAt: Date) {
            self.day = day
            self.totals = totals
            self.countedAt = countedAt
        }
    }

    /// The remembered totals, if they belong to the day `now` falls in.
    package static func load(
        now: Date = Date(),
        from defaults: UserDefaults = .standard
    ) -> Entry? {
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        guard entry.day == Calendar.current.startOfDay(for: now) else { return nil }
        return entry
    }

    package static func save(
        _ totals: TokenTotals,
        now: Date = Date(),
        to defaults: UserDefaults = .standard
    ) {
        let entry = Entry(
            day: Calendar.current.startOfDay(for: now),
            totals: totals,
            countedAt: now
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: key)
    }

    /// Package-visible so the checks can work in an isolated defaults suite
    /// without touching the real preferences.
    package static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
