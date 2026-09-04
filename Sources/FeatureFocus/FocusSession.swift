import Foundation

/// A piece of the cycle that is currently running, kept somewhere it survives
/// the screen going away and the app being quit.
///
/// The same reasoning the countdown already follows: a focus block is a
/// deadline somebody set for themselves, not a reading about the machine, so
/// holding on to it while the screen is off reads nothing and asks the system
/// for nothing. Losing it would be worse here than for a plain timer — a
/// twenty-five minute block is longer than the display takes to sleep, so
/// dropping it on lock would mean the feature never once survived being used
/// as intended.
public struct FocusSession: Codable, Equatable {
    public let block: FocusBlock
    public let startedAt: Date
    public let endsAt: Date

    public init(block: FocusBlock, startedAt: Date, endsAt: Date) {
        self.block = block
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    public var total: TimeInterval { max(0, endsAt.timeIntervalSince(startedAt)) }

    public func secondsLeft(now: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    public func fractionDone(now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / total))
    }

    /// How much of this block had actually been served by a given moment.
    /// Never more than the block is long, so a session found long after it was
    /// due cannot credit a day with hours it did not have.
    public func servedSeconds(by moment: Date) -> TimeInterval {
        min(total, max(0, moment.timeIntervalSince(startedAt)))
    }
}

/// Where the session and the day's tally are kept between launches.
package enum FocusStore {
    package static let sessionKey = "hashnotch.focus.session.v1"
    package static let tallyKey = "hashnotch.focus.tally.v1"

    package static func loadSession(from defaults: UserDefaults) -> FocusSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(FocusSession.self, from: data)
    }

    package static func save(_ session: FocusSession?, to defaults: UserDefaults) {
        guard let session, let data = try? JSONEncoder().encode(session) else {
            defaults.removeObject(forKey: sessionKey)
            return
        }
        defaults.set(data, forKey: sessionKey)
    }

    package static func loadTally(from defaults: UserDefaults) -> FocusTally? {
        guard let data = defaults.data(forKey: tallyKey) else { return nil }
        return try? JSONDecoder().decode(FocusTally.self, from: data)
    }

    package static func save(_ tally: FocusTally, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(tally) else { return }
        defaults.set(data, forKey: tallyKey)
    }

    package static func loadPlan(from defaults: UserDefaults) -> FocusPlan {
        guard let data = defaults.data(forKey: "hashnotch.focus.plan.v1"),
              let plan = try? JSONDecoder().decode(FocusPlan.self, from: data)
        else { return FocusPlan() }
        return plan.clamped
    }

    package static func save(_ plan: FocusPlan, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(plan.clamped) else { return }
        defaults.set(data, forKey: "hashnotch.focus.plan.v1")
    }
}

/// What to do about a session found on the way back.
package enum FocusResumption: Equatable {
    /// Still to come: pick it up where it left off.
    case resume(FocusSession)
    /// It came due while nobody was watching. Count what it served and move on.
    case ranOut(FocusSession)
}

package enum FocusResume {
    /// Whether a session found in storage is still running or has since ended.
    package static func decide(_ session: FocusSession, now: Date) -> FocusResumption {
        now < session.endsAt ? .resume(session) : .ranOut(session)
    }
}
