import Foundation

/// The countdown somebody set, kept somewhere it survives the screen going
/// away.
///
/// **Why this exists at all.** A running timer used to live only in the
/// engine's own memory, and the engine is stopped whenever the island leaves
/// the screen — which is every time the Mac is locked and every time the
/// display goes to sleep. Stopping it set the phase back to idle, so a
/// twenty-five minute timer set at the desk was silently gone by the time
/// anybody came back to it: no countdown, no chime, no notification, and
/// nothing anywhere saying a timer had ever been started. The display sleeping
/// after ten minutes is not an edge case for a twenty-five minute timer; it is
/// the ordinary way one is used.
///
/// A deadline is not a reading. Everything else the app stops on lock is
/// something it was measuring about the machine or the person, and stopping it
/// is the point. This is a date somebody typed in themselves, and holding on to
/// it while the screen is off reads nothing, opens nothing, and asks the system
/// for nothing.
package struct TimerDeadline: Codable, Equatable {
    /// When it is due.
    package let endsAt: Date
    /// How long it was set for, which is what the progress bar is drawn
    /// against. Kept rather than recomputed, because "how far through" cannot
    /// be worked out from the end alone.
    package let total: TimeInterval

    /// Whether the alert for this deadline was handed to the system when the
    /// timer started.
    ///
    /// It decides one thing and it is worth the field: whether the app should
    /// make a noise about a deadline it finds already past. If the system was
    /// given the alert, the system has already made it — on time, which is the
    /// whole reason it was handed over — and a chime on the next launch would
    /// be a second alert for one timer, arriving whenever the Mac was next
    /// opened. If it was not, nothing has been announced at all and the chime
    /// is the only alert there will ever be.
    package let alertScheduled: Bool

    package init(endsAt: Date, total: TimeInterval, alertScheduled: Bool = false) {
        self.endsAt = endsAt
        self.total = total
        self.alertScheduled = alertScheduled
    }

    /// Read leniently, so a deadline written by an older build — which had no
    /// such field — still loads. Missing means nothing was handed to the
    /// system, which is the reading that alerts rather than the one that goes
    /// quiet.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        total = try container.decode(TimeInterval.self, forKey: .total)
        alertScheduled = try container.decodeIfPresent(Bool.self, forKey: .alertScheduled) ?? false
    }
}

/// What to do about a deadline found on the way back.
package enum TimerResumption: Equatable {
    /// Still to come: pick the countdown up where it left off.
    case resume(TimerDeadline)
    /// It came due while the app was not watching. Say so, and say when — and
    /// the whole deadline comes back, because whether an alert was left with
    /// the system decides whether the app should make a sound about it.
    case finished(TimerDeadline)
    /// It came due so long ago that announcing it now would be noise rather
    /// than news.
    case expired
}

package enum TimerRestore {
    /// How late an alert may be and still be worth making.
    ///
    /// A timer that ended four minutes ago, while the display was asleep, is
    /// news: somebody is standing here now and the thing they asked to be told
    /// about has happened. A timer that ended overnight, because the Mac was
    /// shut, is not — whatever it was for is long past, and a chime at nine in
    /// the morning for a timer set at six the previous evening is the app being
    /// startling rather than useful.
    ///
    /// An hour, and there is no right answer to defend here — only the two
    /// wrong ones either side of it. Announcing everything means being woken by
    /// yesterday; announcing nothing means the commonest case of all, a display
    /// that slept through the last two minutes, goes unmentioned.
    package static let catchUpWindow: TimeInterval = 60 * 60

    /// What a deadline found at `now` should do.
    package static func resumption(from deadline: TimerDeadline?, now: Date) -> TimerResumption? {
        guard let deadline else { return nil }
        if deadline.endsAt > now { return .resume(deadline) }
        if now.timeIntervalSince(deadline.endsAt) <= catchUpWindow {
            return .finished(deadline)
        }
        return .expired
    }

    /// How the alert names a finish that is being reported late.
    ///
    /// The plain "your timer is done" is true for one of these and misleading
    /// for the other: read at 14:05, it says the timer just ended, and a timer
    /// that actually ended at 13:58 while the screen was asleep did not. So a
    /// late one says when, and an on-time one does not say anything it does not
    /// need to.
    package static func finishedBody(endedAt: Date, now: Date, calendar: Calendar = .current) -> String {
        // Under a minute is not late enough to be worth qualifying — the delay
        // is the length of a tick, not a gap somebody would notice.
        guard now.timeIntervalSince(endedAt) >= 60 else {
            return "Your HashNotch timer is done."
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = calendar.isDateInToday(endedAt) ? "HH:mm" : "d MMM, HH:mm"
        return "Your HashNotch timer ended at \(formatter.string(from: endedAt))."
    }
}

/// Where the deadline is kept between runs — the same shape as every other
/// record this app keeps, so it can be handed a throwaway store in a check.
package enum TimerDeadlineStore {
    package static let key = "hashnotch.timer.deadline"

    package static func load(from defaults: UserDefaults = .standard) -> TimerDeadline? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TimerDeadline.self, from: data)
    }

    package static func save(_ deadline: TimerDeadline, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(deadline) else { return }
        defaults.set(data, forKey: key)
    }

    package static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// How long a timer is set for: the rules for the stepper, out where they can
/// be measured.
///
/// They lived in the view's body, which is where nearly every bug in this app
/// has been found — a decision that cannot be asked a question without drawing
/// something first.
package enum TimerLength {
    /// The shortest and longest a timer may be set for. Ten hours is not a
    /// useful timer, but it is a harmless one, and a ceiling has to be
    /// somewhere.
    package static let shortest = 1
    package static let longest = 600

    /// The length the stepper starts at the very first time.
    package static let initial = 10

    /// Coarser steps at higher values, so a long timer is quick to dial without
    /// making a short one clumsy.
    package static func step(for minutes: Int) -> Int {
        if minutes >= 60 { return 15 }
        if minutes >= 20 { return 5 }
        return 1
    }

    /// One press of minus or plus, kept inside the ends.
    package static func adjusted(_ minutes: Int, by direction: Int) -> Int {
        clamped(minutes + step(for: minutes) * direction)
    }

    package static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, shortest), longest)
    }
}

/// The length last chosen, remembered between panels and between launches.
///
/// It was `@State` on the detail view, which is rebuilt every time the panel
/// opens — so a length somebody had dialled up to 45 was back at 10 the next
/// time they hovered the notch, and dialling it again is nine presses.
package enum TimerLengthStore {
    package static let key = "hashnotch.timer.minutes"

    package static func load(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: key)
        // `integer(forKey:)` answers 0 for a key that was never written, which
        // is not a length. Nothing set means the first-time value rather than
        // the shortest one.
        guard stored > 0 else { return TimerLength.initial }
        return TimerLength.clamped(stored)
    }

    package static func save(_ minutes: Int, to defaults: UserDefaults = .standard) {
        defaults.set(TimerLength.clamped(minutes), forKey: key)
    }
}
