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
    /// Whether the system was handed the alert for this block.
    ///
    /// It decides one thing and it is worth the field: whether the app should
    /// make a noise about a block it finds already over. If the system has the
    /// alert, the system has already made it — on time, which is the whole
    /// reason it was handed over — and a chime on the next launch would be a
    /// second alert for one block, arriving whenever the Mac was next opened.
    public let alertScheduled: Bool

    public init(block: FocusBlock, startedAt: Date, endsAt: Date, alertScheduled: Bool = false) {
        self.block = block
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.alertScheduled = alertScheduled
    }

    /// Read leniently, so a session written by a build without this field still
    /// loads. Missing means nothing was handed over, which is the reading that
    /// alerts rather than the one that goes quiet.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        block = try container.decode(FocusBlock.self, forKey: .block)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        alertScheduled = try container.decodeIfPresent(Bool.self, forKey: .alertScheduled) ?? false
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
