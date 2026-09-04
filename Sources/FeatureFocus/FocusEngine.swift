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

    private var ticker: PollingSampler?
    private weak var presence: LivePresence?
    private var defaults: UserDefaults = .standard
    private var awayWatch: AnyCancellable?
    private var lastAwayHandled: AwaySpell?

    public init() {}

    public var isRunning: Bool { session != nil }

    public func start(presence: LivePresence, away: AwayReport, defaults: UserDefaults = .standard) {
        self.presence = presence
        self.defaults = defaults
        plan = FocusStore.loadPlan(from: defaults)
        tally = FocusTallyMath.current(FocusStore.loadTally(from: defaults), now: Date())

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
        let running = FocusSession(
            block: next,
            startedAt: started,
            endsAt: started.addingTimeInterval(plan.seconds(for: next))
        )
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
        // The day can turn over under a running block.
        let rolled = FocusTallyMath.current(tally, now: now)
        if rolled != tally { tally = rolled; FocusStore.save(tally, to: defaults) }

        guard let running = session, now >= running.endsAt else { return }
        complete(running, at: running.endsAt)
    }

    /// A block that reached its end. It is added to the day and the next part
    /// begins on its own — a cycle that waited to be told to carry on would be
    /// a cycle nobody completes.
    private func complete(_ running: FocusSession, at moment: Date) {
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
        updatePresence()
    }

    /// A spell with the screen away, applied to whatever was running.
    ///
    /// A piece of work you walked out of is not a piece of work you did, so it
    /// ends at the moment you left, counts only what it had served by then, and
    /// is recorded as abandoned. A break is different: being away IS the break,
    /// so it is left to run.
    private func reconcileAway(_ spell: AwaySpell?) {
        guard let spell, spell != lastAwayHandled else { return }
        lastAwayHandled = spell

        guard let running = FocusStore.loadSession(from: defaults) ?? session else {
            tally = FocusTallyMath.addingAway(
                FocusTallyMath.current(tally, now: spell.returnedAt), seconds: spell.seconds
            )
            FocusStore.save(tally, to: defaults)
            return
        }
        guard running.block.isWork, spell.leftAt < running.endsAt else { return }
        session = running
        end(running, at: spell.leftAt, completed: false)
        tally = FocusTallyMath.addingAway(tally, seconds: spell.seconds)
        FocusStore.save(tally, to: defaults)
    }

    private func updatePresence() {
        presence?.setActive("focus", session != nil)
    }
}
