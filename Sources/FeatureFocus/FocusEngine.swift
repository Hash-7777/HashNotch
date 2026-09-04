import Combine
import Foundation
import HashNotchKit

/// Runs the cycle and keeps the day's tally.
///
/// The rules it applies all live elsewhere, in `FocusPlan` and `FocusTallyMath`,
/// so what happens at the end of a block and what a day comes to can both be
/// checked without living through either. This is the part that holds a clock
/// and a store.
@MainActor
public final class FocusEngine: ObservableObject {
    @Published public private(set) var session: FocusSession?
    @Published public private(set) var tally = FocusTally(day: FocusTallyMath.day(of: Date()))
    @Published public private(set) var now = Date()
    @Published public private(set) var plan = FocusPlan()
    @Published public private(set) var history = FocusHistory()

    private var ticker: PollingSampler?
    private weak var presence: LivePresence?
    private var defaults: UserDefaults = .standard
    private var awayWatch: AnyCancellable?
    private var lastAwayHandled: AwaySpell?
    /// Its own identifier, so a focus alert and a countdown alert can never
    /// cancel one another.
    private let notifier = DeadlineNotifier(requestIdentifier: "com.hashnotch.focus.block")
    /// Whether the system says it will show a banner. The panel does not promise
    /// what will not happen.
    @Published public private(set) var alertsAllowed: Bool?

    public init() {}

    public var isRunning: Bool { session != nil }

    public func start(presence: LivePresence, away: AwayReport, defaults: UserDefaults = .standard) {
        self.presence = presence
        self.defaults = defaults
        plan = FocusStore.loadPlan(from: defaults)
        notifier.onAllowedChanged = { [weak self] allowed in
            MainActor.assumeIsolated { self?.alertsAllowed = allowed }
        }
        history = FocusHistoryStore.load(from: defaults)
        rollOver(FocusStore.loadTally(from: defaults), now: Date())

        // A spell away may have ended a block while nobody was watching. Settle
        // that BEFORE picking a session up, so a block that was walked out of is
        // not first resumed and then abandoned.
        reconcileAway(away.lastReturn)
        awayWatch = away.$lastReturn.sink { [weak self] spell in
            MainActor.assumeIsolated { self?.reconcileAway(spell) }
        }

        if let kept = FocusStore.loadSession(from: defaults) {
            switch FocusResume.decide(kept, now: Date()) {
            case .resume(let live):
                session = live
                // A block picked up after a relaunch may never have been handed
                // to the system — an older build wrote no such field, and
                // permission may have been refused when it started and granted
                // since. Without this it would run to its end in silence, which
                // is the one case somebody would never think to test.
                if !live.alertScheduled { rescheduleAlert(for: live) }
            case .ranOut(let done):
                complete(done, at: done.endsAt)
            }
        }
        updatePresence()
        startTicking()
    }

    public func stop() {
        ticker?.stop()
        ticker = nil
        awayWatch = nil
        notifier.cancelScheduled()
        presence?.setActive("focus", false)
    }

    /// The screen went away. The session stays on disk — it is a deadline
    /// somebody set, not a reading — and the clock stops because nothing is on
    /// screen to count down.
    public func suspend() {
        ticker?.stop()
        ticker = nil
        awayWatch = nil
    }

    // MARK: Driving the cycle

    /// Begin, or begin the next thing. Called by the button in the panel.
    public func begin(_ block: FocusBlock? = nil) {
        let next = block ?? plan.next(after: .shortBreak, finishedWorkBlocks: tally.finishedWork)
        let started = Date()
        let endsAt = started.addingTimeInterval(plan.seconds(for: next))
        let after = plan.next(after: next, finishedWorkBlocks: tally.finishedWork + (next.isWork ? 1 : 0))

        // Asked every time a block starts rather than once, which is what
        // catches permission being taken away later. The deadline is handed
        // over inside the answer, because whether the system will show a banner
        // decides whether it is worth handing over at all.
        notifier.prepare { [weak self] in
            guard let self, let running = self.session, running.startedAt == started else { return }
            let scheduled = self.notifier.schedule(
                at: endsAt,
                title: FocusAlert.title(for: next),
                body: FocusAlert.body(next: after, plan: self.plan)
            )
            guard scheduled else { return }
            let stamped = FocusSession(
                block: running.block, startedAt: running.startedAt,
                endsAt: running.endsAt, alertScheduled: true
            )
            self.session = stamped
            FocusStore.save(stamped, to: self.defaults)
        }

        let running = FocusSession(block: next, startedAt: started, endsAt: endsAt)
        session = running
        FocusStore.save(running, to: defaults)
        updatePresence()
    }

    /// Stop what is running without finishing it. A piece of work ended this way
    /// counts the time it actually served and is recorded as abandoned, because
    /// it was.
    public func giveUp() {
        guard let running = session else { return }
        end(running, at: Date(), completed: false)
    }

    /// Finish what is running early and move straight on to the next part.
    public func skip() {
        guard let running = session else { return }
        end(running, at: Date(), completed: running.block.isWork ? false : true)
        begin(plan.next(after: running.block, finishedWorkBlocks: tally.finishedWork))
    }

    public func setPlan(_ new: FocusPlan) {
        plan = new.clamped
        FocusStore.save(plan, to: defaults)
    }

    // MARK: The clock

    private func startTicking() {
        ticker?.stop()
        let ticker = PollingSampler(interval: 1) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.ticker = ticker
        ticker.start()
    }

    private func tick() {
        now = Date()
        // The day can turn over under a running block. Yesterday is put away
        // rather than dropped — that is the whole point of keeping any of this.
        rollOver(tally, now: now)

        guard let running = session, now >= running.endsAt else { return }
        complete(running, at: running.endsAt)
    }

    /// A block that reached its end. It is added to the day and the next part
    /// begins on its own — a cycle that waited to be told to carry on would be
    /// a cycle nobody completes.
    private func complete(_ running: FocusSession, at moment: Date) {
        // Exactly one alert. If the system was given the deadline it has already
        // made the noise, on time, and a chime here would be a second one at the
        // wrong moment — the app's notice of a finish can be minutes late where
        // the system's never is.
        if !running.alertScheduled { notifier.chimeNow() }
        end(running, at: moment, completed: true)
        begin(plan.next(after: running.block, finishedWorkBlocks: tally.finishedWork))
    }

    private func end(_ running: FocusSession, at moment: Date, completed: Bool) {
        tally = FocusTallyMath.adding(
            FocusTallyMath.current(tally, now: moment),
            block: running.block,
            seconds: running.servedSeconds(by: moment),
            completed: completed
        )
        FocusStore.save(tally, to: defaults)
        session = nil
        FocusStore.save(nil, to: defaults)
        // A block that is over must not still go off at the moment it would
        // have ended. A cancelled deadline that alerts anyway is worse than one
        // that never existed.
        notifier.cancelScheduled()
        updatePresence()
    }

    /// A spell with the screen away, applied to whatever was running.
    ///
    /// A round you walked out of is not a round you did, so it ends at the
    /// moment you left and counts only what it had served by then — never as
    /// finished. A rest is different: being away IS the rest, so it runs on.
    private func reconcileAway(_ spell: AwaySpell?) {
        guard let spell, spell != lastAwayHandled else { return }
        lastAwayHandled = spell

        guard let running = FocusStore.loadSession(from: defaults) ?? session else { return }
        guard running.block.isWork, spell.leftAt < running.endsAt else { return }
        session = running
        end(running, at: spell.leftAt, completed: false)
    }

    /// Move to today's tally, keeping yesterday if there was anything in it.
    private func rollOver(_ kept: FocusTally?, now: Date) {
        let today = FocusTallyMath.day(of: now)
        if let kept, kept.day != today {
            history = FocusHistoryMath.archiving(history, finished: kept)
            FocusHistoryStore.save(history, to: defaults)
        }
        let next = FocusTallyMath.current(kept, now: now)
        guard next != tally else { return }
        tally = next
        FocusStore.save(tally, to: defaults)
    }

    /// Forget the days behind today. Offered because a record of somebody's
    /// working days is theirs to end, and a promise to keep only a week is worth
    /// less than a button that empties it now.
    public func clearHistory() {
        history = FocusHistory()
        FocusHistoryStore.clear(from: defaults)
    }

    /// Hand a round already in progress to the system, if it will take it.
    private func rescheduleAlert(for running: FocusSession) {
        let after = plan.next(
            after: running.block,
            finishedWorkBlocks: tally.finishedWork + (running.block.isWork ? 1 : 0)
        )
        notifier.prepare { [weak self] in
            guard let self, let live = self.session, live.startedAt == running.startedAt else { return }
            let scheduled = self.notifier.schedule(
                at: live.endsAt,
                title: FocusAlert.title(for: live.block),
                body: FocusAlert.body(next: after, plan: self.plan)
            )
            guard scheduled else { return }
            let stamped = FocusSession(
                block: live.block, startedAt: live.startedAt,
                endsAt: live.endsAt, alertScheduled: true
            )
            self.session = stamped
            FocusStore.save(stamped, to: self.defaults)
        }
    }

    private func updatePresence() {
        presence?.setActive("focus", session != nil)
    }
}
