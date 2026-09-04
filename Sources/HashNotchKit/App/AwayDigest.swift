import Foundation

/// What happened while nobody was looking.
///
/// Every other readout in this app answers *right now*. This is the only one
/// that answers *what did I miss* — and macOS answers it nowhere at all. You
/// shut the lid, come back two hours later, and the machine tells you nothing
/// about the time it spent alone: not that a download finished, not that three
/// gigabytes went out, not that the battery fell eighteen points in a bag.
///
/// It reads **nothing new** to do it. Every number here is one a feature was
/// already keeping and already showing; this subtracts two of them. For an app
/// whose consent window lists everything it reads before it reads anything,
/// that matters more than the feature does.
public enum AwayUnit: String, Sendable, Equatable {
    /// Bytes through the interfaces. Only ever climbs.
    case bytes
    /// A level that moves both ways, said with its sign — the battery.
    case percent
    /// A tally of things that happened. Only ever climbs.
    case count
    /// A large tally, said short: 780K rather than 780,412.
    case compact
}

/// One number a feature is willing to have compared across a spell away.
///
/// Features supply these and know nothing about the digest; the core reads them
/// and knows nothing about the features. Neither end has to be told the other
/// exists, which is the same seam every other shared thing in this app uses.
public struct AwayFigure: Sendable, Equatable {
    /// Stable across a spell away — it is what the two snapshots are matched on,
    /// so it must not be the feature's display name.
    public let id: String
    /// What is being counted, in the singular: "download", "byte", "battery".
    public let noun: String
    /// Any words that follow the number: "finished", "used".
    public let suffix: String
    public let value: Double
    public let unit: AwayUnit

    public init(id: String, noun: String, suffix: String = "", value: Double, unit: AwayUnit) {
        self.id = id
        self.noun = noun
        self.suffix = suffix
        self.value = value
        self.unit = unit
    }
}

/// Everything a feature reported at one moment.
public struct AwaySnapshot: Sendable, Equatable {
    public let at: Date
    public let figures: [AwayFigure]

    public init(at: Date, figures: [AwayFigure]) {
        self.at = at
        self.figures = figures
    }
}

/// What changed in one figure across the whole spell.
public struct AwayChange: Sendable, Equatable {
    public let figure: AwayFigure
    public let delta: Double

    public init(figure: AwayFigure, delta: Double) {
        self.figure = figure
        self.delta = delta
    }
}

/// The rules, kept pure so every one of them can be checked. There is no way to
/// stage a two-hour absence inside a check, and a digest that is only ever seen
/// after a real one is a digest nobody can test.
public enum AwayDigest {
    /// The shortest absence worth a word.
    ///
    /// Somebody stepping away for ninety seconds does not need telling what they
    /// missed, and a panel that greets every unlock stops being read within a
    /// day. That is the failure this number exists to prevent: the danger here
    /// is not being wrong, it is being ignorable.
    public static let shortestWorthReporting: TimeInterval = 5 * 60

    /// A change too small to be worth a line, per unit. Coming back to "0 MB
    /// used" is noise wearing the shape of news.
    public static func isWorthSaying(_ change: AwayChange) -> Bool {
        switch change.figure.unit {
        case .bytes: return change.delta >= 1_000_000
        case .percent: return abs(change.delta) >= 3
        case .count: return change.delta >= 1
        case .compact: return change.delta >= 1_000
        }
    }

    /// Which figures actually moved, in the order the features gave them.
    ///
    /// A figure that was not in both snapshots is dropped rather than guessed
    /// at: a feature switched on while you were away has no "before", and
    /// treating its whole total as the change would report a day's data as five
    /// minutes' worth.
    public static func changes(from before: AwaySnapshot, to after: AwaySnapshot) -> [AwayChange] {
        after.figures.compactMap { now in
            guard let then = before.figures.first(where: { $0.id == now.id }) else { return nil }
            let delta = now.value - then.value
            // A counter that went backwards was reset under us — midnight, or a
            // feature restarting. There is nothing true to say about it.
            if now.unit != .percent && delta < 0 { return nil }
            let change = AwayChange(figure: now, delta: delta)
            return isWorthSaying(change) ? change : nil
        }
    }

    /// Whether there is anything to show at all.
    public static func isWorthShowing(awayFor seconds: TimeInterval, changes: [AwayChange]) -> Bool {
        seconds >= shortestWorthReporting && !changes.isEmpty
    }

    /// The whole decision, in one place: compare the two moments, and either
    /// return something worth showing or nothing at all.
    ///
    /// Here rather than in the coordinator so that a spell away can be handed
    /// in rather than waited through. There is no way to be gone for two hours
    /// inside a check, and a rule that can only be exercised by actually
    /// leaving is a rule nobody exercises.
    public static func result(
        from before: AwaySnapshot,
        to after: AwaySnapshot
    ) -> (line: String, changes: [AwayChange], awayFor: TimeInterval)? {
        let seconds = after.at.timeIntervalSince(before.at)
        let changed = changes(from: before, to: after)
        guard isWorthShowing(awayFor: seconds, changes: changed) else { return nil }
        return (line(awayFor: seconds, changes: changed), changed, seconds)
    }

    /// How long you were gone, in the fewest words that are still true.
    public static func awayText(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 60 { return "Away \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "Away \(hours) hr" }
        return "Away \(hours) hr \(rest) min"
    }

    /// One change, said the way that unit is said.
    public static func text(for change: AwayChange) -> String {
        let figure = change.figure
        switch figure.unit {
        case .bytes:
            return join(Formatters.bytes(Int64(change.delta)), figure.suffix)
        case .percent:
            // The sign is the point. A battery that fell fourteen points in a
            // bag is the alarming half of this whole feature, and "14%" without
            // it could just as easily be good news.
            let rounded = Int(change.delta.rounded())
            let sign = rounded < 0 ? "\u{2212}" : "+"
            return join("\(figure.noun) \(sign)\(abs(rounded))%", figure.suffix)
        case .count:
            let whole = Int(change.delta.rounded())
            let noun = whole == 1 ? figure.noun : figure.noun + "s"
            return join("\(whole) \(noun)", figure.suffix)
        case .compact:
            return join("\(Formatters.compactCount(Int64(change.delta))) \(figure.noun)s", figure.suffix)
        }
    }

    /// The whole line, as the island says it.
    public static func line(awayFor seconds: TimeInterval, changes: [AwayChange]) -> String {
        ([awayText(seconds)] + changes.map(text(for:))).joined(separator: " · ")
    }

    private static func join(_ head: String, _ suffix: String) -> String {
        suffix.isEmpty ? head : head + " " + suffix
    }
}
