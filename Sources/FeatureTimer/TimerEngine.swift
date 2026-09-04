import AppKit
import SwiftUI
import HashNotchKit

/// A countdown the user starts from the panel. While running it is a live
/// activity (compact countdown flanking the notch); when it is due, the alert
/// arrives and the panel says "Time's up" briefly.
///
/// **The deadline, not the countdown, is the timer.** What is kept is the
/// moment it is due — see `TimerDeadline` — and everything else is worked out
/// from that and the clock. That is what lets the countdown survive the island
/// leaving the screen, which happens every time the Mac is locked and every
/// time the display sleeps. It used to not survive it: stopping the feature set
/// the phase back to idle and dropped the deadline, so a timer set at the desk
/// was silently gone by the time anybody came back, with no alert and nothing
/// saying one had been set.
@MainActor
public final class TimerEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case running(endsAt: Date, total: TimeInterval)
        case finished
    }

    @Published public private(set) var phase: Phase = .idle
    /// Ticks once a second while running so countdown text stays live.
    @Published public private(set) var now = Date()
    /// Whether the system will show a banner when the timer is up. `nil` until
    /// a timer has been started and the question has been asked.
    ///
    /// Published because the panel says so when the answer is no. An app that
    /// has been refused notification permission and goes on looking exactly as
    /// if it had not is an app that quietly stops doing what it says.
    @Published public private(set) var notificationsAllowed: Bool?

    /// The length the stepper offers, which is whatever was set last.
    @Published public var preferredMinutes: Int {
        didSet {
            let clamped = TimerLength.clamped(preferredMinutes)
            if clamped != preferredMinutes {
                preferredMinutes = clamped
                return
            }
            TimerLengthStore.save(clamped, to: defaults)
        }
    }

    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var finishWork: DispatchWorkItem?
    private let notifier = DeadlineNotifier(requestIdentifier: "com.hashnotch.timer.deadline")
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredMinutes = TimerLengthStore.load(from: defaults)
        notifier.onAllowedChanged = { [weak self] allowed in
            self?.notificationsAllowed = allowed
        }
    }

    /// Coming up, whether from launch, from being switched on, or from the
    /// screen coming back. A deadline still to come is picked up where it left
    /// off; one that came due while nothing was watching is announced, with
    /// when it happened, unless it is old enough that saying so would be noise.
    public func start(presence: LivePresence) {
        self.presence = presence
        switch TimerRestore.resumption(from: TimerDeadlineStore.load(from: defaults), now: Date()) {
        case .resume(let deadline):
            phase = .running(endsAt: deadline.endsAt, total: deadline.total)
            presence.setActive("timer", true)
            beginTicking()
        case .finished(let deadline):
            // Silent when the system was given this one: it announced it at the
            // right moment, and this is only the app catching up with something
            // that has already been said.
            announceFinish(endedAt: deadline.endsAt, chiming: !deadline.alertScheduled)
        case .expired:
            TimerDeadlineStore.clear(from: defaults)
        case nil:
            break
        }
    }

    /// The user switched the timer off. Off means off: the countdown goes, and
    /// so does the alert that was handed to the system for it — an alert left
    /// scheduled would go off for a timer that no longer exists.
    public func stop() {
        suspend()
        phase = .idle
        TimerDeadlineStore.clear(from: defaults)
        notifier.cancelScheduled()
        presence?.setActive("timer", false)
    }

    /// The screen went away. Stop the work, keep the deadline.
    ///
    /// Nothing is read by a countdown, so there is nothing here to stop
    /// reading — what stops is a once-a-second wakeup that would be spent
    /// drawing to a screen nobody can see. The deadline stays, and the alert
    /// stays with the system, which is what makes a timer set before a lunch
    /// break still go off during it.
    public func suspend() {
        sampler?.stop()
        sampler = nil
        finishWork?.cancel()
        finishWork = nil
        // "Time's up" is an announcement with a life of eight seconds, and the
        // thing that ends it is a timer that suspending has just cancelled.
        // Left as it is, a finish that happened just before the screen went
        // away would still be sitting there hours later with nothing left to
        // clear it.
        if phase == .finished {
            phase = .idle
            presence?.setActive("timer", false)
        }
    }

    // MARK: User actions

    public func begin(minutes: Int) {
        finishWork?.cancel()
        let total = TimeInterval(minutes * 60)
        let endsAt = Date().addingTimeInterval(total)
        phase = .running(endsAt: endsAt, total: total)
        // Asked every time rather than once, because permission can be taken
        // away as easily as it was given, and the answer decides which of the
        // two alerts this timer gets.
        //
        // The alert is handed over TWICE, and the second time is the one that
        // matters. On a Mac that has never been asked, the answer arrives from
        // a window the person has yet to look at, so the first attempt is made
        // without knowing — and an alert offered to the system before it has
        // agreed to show any is an alert that may simply be dropped. That is
        // the first timer anybody ever sets, which is a poor one to lose. So it
        // is offered again once the answer is in, under the same identifier,
        // which replaces rather than duplicates.
        recordDeadline(endsAt: endsAt, total: total)
        notifier.prepare { [weak self] in
            guard let self, case .running(let endsAt, let total) = self.phase else { return }
            self.recordDeadline(endsAt: endsAt, total: total)
        }
        presence?.setActive("timer", true)
        beginTicking()
    }

    public func cancel() {
        stop()
    }

    // MARK: Progress

    public func secondsLeft(now: Date) -> Int {
        guard case .running(let endsAt, _) = phase else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded()))
    }

    public func fractionDone(now: Date) -> Double {
        guard case .running(let endsAt, let total) = phase, total > 0 else { return 0 }
        return min(max(1 - endsAt.timeIntervalSince(now) / total, 0), 1)
    }

    // MARK: Running

    private static let alertTitle = "Timer finished"

    /// Hand the deadline to the system if it will take it, and write down which
    /// of the two of them is going to do the announcing.
    private func recordDeadline(endsAt: Date, total: TimeInterval) {
        let scheduled = notifier.schedule(
            at: endsAt, title: Self.alertTitle,
            body: TimerRestore.finishedBody(endedAt: endsAt, now: endsAt))
        TimerDeadlineStore.save(
            TimerDeadline(endsAt: endsAt, total: total, alertScheduled: scheduled),
            to: defaults)
    }

    private func beginTicking() {
        sampler = PollingSampler(interval: 1.0) { [weak self] in self?.tick() }
        sampler?.start()
    }

    private func tick() {
        now = Date()
        guard case .running(let endsAt, _) = phase else { return }
        if endsAt.timeIntervalSince(now) <= 0 {
            // Here the app is awake and has this launch's answer about whether
            // a banner is coming, so it can simply use it.
            announceFinish(endedAt: endsAt, chiming: notifier.isAllowed != true)
        }
    }

    /// Reach zero now, for the checks.
    ///
    /// The alternative is a check that waits a real minute, which is not a
    /// check anybody runs. What it exercises is the same method the clock
    /// calls, so it cannot drift away from what really happens.
    package func finishNowForChecks() {
        guard case .running(let endsAt, _) = phase else { return }
        announceFinish(endedAt: endsAt, chiming: false)
    }

    /// Say it is up, once, and take the deadline off the books.
    private func announceFinish(endedAt: Date, chiming: Bool) {
        suspend()
        phase = .finished
        TimerDeadlineStore.clear(from: defaults)
        presence?.setActive("timer", true)
        // Already live from the countdown, so the line above changes nothing
        // and announces nothing. This is what tells the island that the same
        // feature now wants a different thing drawn — an orange edge, and the
        // strip itself, which a running countdown does not ask for and a
        // finished one does.
        presence?.changed("timer")

        // Only when the system is not doing it. When a banner is coming, it has
        // already sounded — on time, which the app cannot promise — and a chime
        // here would be a second alert at a later moment.
        if chiming { notifier.chimeNow() }
        // Nothing is left pending either way: an alert for a moment that has
        // already passed has nothing to announce.
        notifier.cancelScheduled()

        // Keep "Time's up" visible briefly, then go quiet.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .finished else { return }
                self.phase = .idle
                self.presence?.setActive("timer", false)
            }
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
    }
}
