import Foundation

/// Which part of a focus cycle a stretch of time belongs to.
public enum FocusBlock: String, Codable, Equatable, Sendable, CaseIterable {
    case work
    case shortBreak
    case longBreak

    public var isWork: Bool { self == .work }

    /// What the island calls it. Short, because it is read at a glance beside a
    /// countdown rather than studied.
    public var label: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long break"
        }
    }
}

/// The shape of the cycle: how long each part runs, and how often the long
/// break comes round.
///
/// Held apart from the engine that runs it so the arithmetic can be checked
/// without waiting twenty-five minutes for it.
public struct FocusPlan: Codable, Equatable, Sendable {
    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// How many pieces of work come before the long break. Four is the usual
    /// answer and the one this starts on.
    public var worksBeforeLongBreak: Int

    public init(
        workMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        worksBeforeLongBreak: Int = 4
    ) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.worksBeforeLongBreak = worksBeforeLongBreak
    }

    /// What each part is worth in minutes, held inside the ranges the settings
    /// offer so a hand-edited preferences file cannot produce a two-second
    /// focus block or a nine-hour one.
    public static let workRange: ClosedRange<Int> = 5...90
    public static let shortBreakRange: ClosedRange<Int> = 1...30
    public static let longBreakRange: ClosedRange<Int> = 5...60
    public static let worksBeforeLongBreakRange: ClosedRange<Int> = 2...8

    public var clamped: FocusPlan {
        FocusPlan(
            workMinutes: min(max(workMinutes, Self.workRange.lowerBound), Self.workRange.upperBound),
            shortBreakMinutes: min(max(shortBreakMinutes, Self.shortBreakRange.lowerBound), Self.shortBreakRange.upperBound),
            longBreakMinutes: min(max(longBreakMinutes, Self.longBreakRange.lowerBound), Self.longBreakRange.upperBound),
            worksBeforeLongBreak: min(max(worksBeforeLongBreak, Self.worksBeforeLongBreakRange.lowerBound), Self.worksBeforeLongBreakRange.upperBound)
        )
    }

    public func minutes(for block: FocusBlock) -> Int {
        let safe = clamped
        switch block {
        case .work: return safe.workMinutes
        case .shortBreak: return safe.shortBreakMinutes
        case .longBreak: return safe.longBreakMinutes
        }
    }

    public func seconds(for block: FocusBlock) -> TimeInterval {
        TimeInterval(minutes(for: block) * 60)
    }

    /// What follows a block that has just finished.
    ///
    /// `finishedWorkBlocks` counts the work already done TODAY, including the
    /// one that has just ended — so the fourth piece of work is followed by the
    /// long break, and the count carries across a lunch break rather than
    /// resetting because the app was quiet for an hour.
    ///
    /// A break is always followed by work. There is nowhere else for it to go,
    /// and a cycle that could end on a break would be a cycle that quietly
    /// stopped.
    public func next(after block: FocusBlock, finishedWorkBlocks: Int) -> FocusBlock {
        guard block.isWork else { return .work }
        let every = clamped.worksBeforeLongBreak
        return finishedWorkBlocks > 0 && finishedWorkBlocks % every == 0 ? .longBreak : .shortBreak
    }

    /// How many pieces of work remain before the long break.
    public func worksUntilLongBreak(finishedWorkBlocks: Int) -> Int {
        let every = clamped.worksBeforeLongBreak
        let done = finishedWorkBlocks % every
        return done == 0 && finishedWorkBlocks > 0 ? every : every - done
    }
}

/// What the alert says when a block ends.
///
/// A rule rather than two strings built where they are sent, so the wording can
/// be checked — and so the thing it most needs to get right is stated once: an
/// alert that only says what ENDED leaves somebody looking at a banner deciding
/// what to do next. Every one of these names what comes next and how long it
/// runs, because that is the part that gets acted on.
public enum FocusAlert {
    public static func title(for finished: FocusBlock) -> String {
        switch finished {
        case .work: return "Focus done"
        case .shortBreak: return "Break over"
        case .longBreak: return "Long break over"
        }
    }

    public static func body(next: FocusBlock, plan: FocusPlan) -> String {
        let minutes = plan.minutes(for: next)
        switch next {
        case .work: return "Back to work — \(minutes) minutes."
        case .shortBreak: return "Time for a \(minutes) minute rest."
        case .longBreak: return "Time for a long rest — \(minutes) minutes."
        }
    }
}
