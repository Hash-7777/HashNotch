import Foundation

/// Where an answer to a feed question is left for whoever asked it.
///
/// An agent that wants permission cannot watch the screen, so it posts a
/// question with a token and waits for that token to be answered. This is the
/// letterbox: the app files the answer under the token, and the asker — a hook
/// script, in practice — reads it back with `defaults read`.
///
/// **In preferences, deliberately, not in a file.** The app promises in
/// SECURITY.md that it writes no files at all, and its only persistent state is
/// its own settings. Answering questions through its own preference domain
/// keeps that true: nothing new appears on disk that was not already there, and
/// nothing outside this app's own settings is written. Measured across
/// processes at 11 milliseconds, which is well under the time it takes to move
/// a hand off a trackpad.
///
/// Answers are kept only long enough to be collected. This is a letterbox, not
/// a record of what you have allowed — that would be a log of your decisions,
/// which is not something this app has any business keeping.
package enum PermissionAnswers {
    package static let key = "hashnotch.answers.v1"

    /// How many answers are remembered. Small on purpose: an asker that has not
    /// collected its answer within a handful of questions has given up, and the
    /// oldest are dropped rather than accumulating.
    package static let limit = 8

    package enum Decision: String, Sendable {
        case allow
        case deny
    }

    /// File an answer under its token.
    package static func record(
        token: String,
        decision: Decision,
        to defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[token] = "\(decision.rawValue) \(Int(now.timeIntervalSince1970))"
        defaults.set(pruned(stored, limit: limit), forKey: key)
    }

    /// The answer to one question, if it has been given.
    package static func decision(
        for token: String,
        in defaults: UserDefaults = .standard
    ) -> Decision? {
        guard let stored = defaults.dictionary(forKey: key) as? [String: String],
              let value = stored[token]?.split(separator: " ").first
        else { return nil }
        return Decision(rawValue: String(value))
    }

    /// Drop the oldest once there are more than the limit.
    ///
    /// Pure, so the checks can hold it to the limit rather than trusting that a
    /// dictionary written a hundred times a day stays small.
    package static func pruned(_ stored: [String: String], limit: Int) -> [String: String] {
        guard stored.count > limit else { return stored }
        let ordered = stored.sorted { left, right in
            stamp(left.value) > stamp(right.value)
        }
        return Dictionary(uniqueKeysWithValues: ordered.prefix(limit).map { ($0.key, $0.value) })
    }

    private static func stamp(_ value: String) -> Int {
        Int(value.split(separator: " ").last.map(String.init) ?? "") ?? 0
    }

    package static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
