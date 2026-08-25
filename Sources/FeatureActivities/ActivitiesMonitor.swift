import Foundation
import SwiftUI
import HashNotchKit

/// Watches the activity feed and keeps a live `now` clock so countdowns tick.
///
/// Nothing here runs on a schedule unless it has to. The feed is watched rather
/// than polled, the clock runs only while a countdown is actually on screen,
/// and a notice is dismissed by a single timer set for the exact moment it is
/// due. With nothing posted, this costs nothing.
@MainActor
public final class ActivitiesMonitor: ObservableObject {
    @Published public private(set) var activities: [LiveActivity] = []
    @Published public private(set) var now: Date = Date()
    /// Whether the hook installed in the home folder is the one this build
    /// ships. `.unknown` until something has been read, so nothing is claimed
    /// before anything is known.
    @Published public private(set) var hookState: HookState = .unknown


    private let hookQueue = DispatchQueue(label: "com.hashnotch.hookcheck", qos: .utility)
    private var hookCheckedAt: Date = .distantPast

    /// How often the installed hook is looked at again.
    ///
    /// The answer changes exactly once — when somebody runs the installer — and
    /// the notice has to go away when they do, or it teaches people that fixing
    /// the thing it asked for does nothing. A minute is far more often than
    /// that needs, and it is two file reads.
    private static let hookCheckInterval: TimeInterval = 60

    private var watcher: DirectoryWatcher?
    private var sampler: PollingSampler?
    private var clock: PollingSampler?
    private weak var presence: LivePresence?

    /// When each activity was first seen, alongside the activity itself so a
    /// NEW one under a reused id is recognised as new — which matters more than
    /// it sounds, because a poster reuses one id for everything it sends.
    ///
    /// A notice says how long it wants to be shown for, not when it should go:
    /// the writer has no idea when the app will next look at the file. A
    /// request uses the same stamp to say how long it has been waiting.
    private var firstSeen: [String: (activity: LiveActivity, at: Date)] = [:]

    /// When this activity first arrived, for anything that wants to say how
    /// long it has been standing there rather than how long it has left.
    package func arrived(_ activity: LiveActivity) -> Date? { firstSeen[activity.id]?.at }

    /// Answer a question from the panel: file it where the asker is looking,
    /// and take it off the screen now.
    package func answer(_ activity: LiveActivity, _ decision: PermissionAnswers.Decision) {
        guard let token = activity.asks else { return }
        PermissionAnswers.record(token: token, decision: decision)
        answered.insert(token)
        apply(ActivitiesReader.read())
    }

    /// Questions answered from the panel, hidden the moment they are answered
    /// rather than when the asker gets round to taking them down.
    ///
    /// The app files an answer and the ASKER removes its own question, which is
    /// correct — it owns the feed — but it means the box stayed on screen for
    /// as long as the round trip took, and stayed there for ever if the asker
    /// had already given up waiting and exited. Pressing a button and watching
    /// nothing happen is how somebody presses it again.
    ///
    /// A token is forgotten as soon as its question leaves the feed, so this
    /// never grows and never becomes a record of what was allowed.
    private var answered: Set<String> = []

    private var dismissalWork: DispatchWorkItem?

    public init() {}

    /// How long a notice stays, and whether a request waits. The poster
    /// suggests a duration; this is the reader's preference, and the reader
    /// wins — it is your notch.
    private weak var settings: SettingsStore?

    public func start(presence: LivePresence, settings: SettingsStore? = nil) {
        self.presence = presence
        self.settings = settings
        reload()
        refreshHookState()

        // The feed changes when somebody posts, which is rarely and never on a
        // schedule. Watch the folder rather than stat-ing the file forever —
        // the folder, not the file, because the file is replaced by a rename
        // and a file-level watch would go deaf after the first post.
        watcher = DirectoryWatcher(url: ActivitiesReader.feedURL.deletingLastPathComponent()) {
            [weak self] in self?.reload()
        }
        if watcher == nil {
            // The folder does not exist yet, so nothing has ever posted. Look
            // for it occasionally, and switch to watching once it appears.
            sampler = PollingSampler(interval: 3.0) { [weak self] in self?.lookForFolder() }
            sampler?.start()
        }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        sampler?.stop()
        sampler = nil
        clock?.stop()
        clock = nil
        dismissalWork?.cancel()
        dismissalWork = nil
        firstSeen.removeAll()
        presence?.setActive("activities", false)
    }

    /// Nothing has ever posted. As soon as the folder exists, start watching it
    /// and stop looking.
    private func lookForFolder() {
        let folder = ActivitiesReader.feedURL.deletingLastPathComponent()
        guard let watcher = DirectoryWatcher(url: folder, onChange: { [weak self] in
            self?.reload()
        }) else { return }

        self.watcher = watcher
        sampler?.stop()
        sampler = nil
        reload()
    }

    private func reload() {
        apply(ActivitiesReader.read())
        // Riding on the feed rather than on a clock of its own. The feed
        // changes when a tool posts, and somebody who has just run the
        // installer is somebody about to use their tools — so the moment the
        // answer could have changed is a moment this is already awake for. The
        // throttle stops a burst of posts turning into a burst of file reads.
        refreshHookState()
    }

    /// Looks at the installed hook, at most once a minute, off the main thread.
    /// Read the installed hook's version again.
    ///
    /// Public because the settings page connects the hook and then needs the
    /// notice above it to stop saying it is out of date — the alternative is a
    /// page that reports the state it had before the button was pressed.
    public func refreshHookState() {
        let now = Date()
        guard now.timeIntervalSince(hookCheckedAt) >= Self.hookCheckInterval else { return }
        hookCheckedAt = now
        hookQueue.async { [weak self] in
            let state = HookInstallation.currentState()
            Task { @MainActor [weak self] in
                guard let self, state != self.hookState else { return }
                self.hookState = state
            }
        }
    }

    /// Whether this activity has just arrived, and so needs its own clock
    /// started.
    ///
    /// True for anything never seen before, and for anything whose content
    /// differs from the last post under the same id — which is what a genuinely
    /// new alert looks like. False for a re-read of the same one, so its clock
    /// keeps running from when it actually arrived rather than restarting on
    /// every glance at the file.
    ///
    /// **It used to refuse to start a clock for a standing request**, on the
    /// reasoning that only a self-dismissing notice needs one to count down
    /// from. A request needs one too, for the opposite reason: it counts UP,
    /// and how long an answer has been owed is the whole of what it has to say.
    /// Refusing it had two consequences, and both were visible.
    ///
    /// A feed poster reuses one id for everything it sends — the Claude Code
    /// hook posts every notice and every request under `claude-code` — so the
    /// entry left behind by the last notice was still sitting there when a
    /// request arrived. The request inherited it, and the notch reported a
    /// question that had just been asked as having waited seven minutes.
    /// Meanwhile the line that is meant to press harder the longer a request
    /// stands had no arrival to measure from at all, so it never pressed.
    ///
    /// Nothing about a notice changes: a notice with no previous entry is still
    /// fresh, a repeat of the same one is still not, and a request cannot
    /// acquire a dismissal by being stamped, because when it dismisses is
    /// decided by `dismissAfter` and it has none.
    ///
    /// Pure and package-visible: this is the decision that silently swallowed
    /// every repeat alert, so it is pinned by the checks rather than left to be
    /// re-derived by eye.
    package nonisolated static func startsFresh(
        _ activity: LiveActivity,
        previously: LiveActivity?
    ) -> Bool {
        guard let previously else { return true }
        return previously != activity
    }

    private func apply(_ fresh: [LiveActivity]) {
        let moment = Date()

        // Remember when each notice arrived, and forget the ones that have gone.
        //
        // Keyed on the activity's CONTENT, not just its id. Posters reuse an id
        // deliberately — that is how the feed merges — so "same id" says nothing
        // about whether this is the same notice. Recording the arrival time
        // against the id alone meant the second alert from any poster was judged
        // against the first one's clock: already past its three seconds, so it
        // was discarded before it drew. Every "Claude finished" after the very
        // first one was swallowed in silence, which is the worst possible way
        // for an alert to fail.
        //
        // Nothing sweeps the record clean either, which is why it survived: once
        // a notice is dismissed there is no countdown running, no dismissal due,
        // and no file change until the next post, so `apply` is not called again
        // and a stale entry simply waits there for its next victim.
        let ids = Set(fresh.map(\.id))
        firstSeen = firstSeen.filter { ids.contains($0.key) }
        for activity in fresh
        where Self.startsFresh(activity, previously: firstSeen[activity.id]?.activity) {
            firstSeen[activity.id] = (activity, moment)
        }

        // Forget answers whose questions have gone; keep the ones still in the
        // feed, so an answered box does not flicker back while the asker is
        // still on its way to removing it.
        answered = AnsweredQuestions.retained(answered, in: fresh)

        let preferred = settings?.alerts.noticeSeconds
        let showing = fresh.filter { activity in
            if AnsweredQuestions.isHidden(activity, answered: answered) { return false }
            guard !activity.isExpired else { return false }
            guard let seen = firstSeen[activity.id]?.at,
                  let dismissal = activity.dismissalDate(firstSeen: seen, preferring: preferred)
            else { return true }
            return dismissal > moment
        }

        if showing != activities { activities = showing }
        presence?.setActive("activities", !activities.isEmpty)
        scheduleNextDismissal(from: moment)
        updateClock()
    }

    /// The one-second clock exists only to move countdown digits. A notice
    /// draws no timer, and an empty island needs no clock at all.
    private func updateClock() {
        let needsClock = activities.contains(where: \.showsCountdown)
        if needsClock, clock == nil {
            now = Date()
            let clock = PollingSampler(interval: 1.0) { [weak self] in
                guard let self else { return }
                self.now = Date()
                // A countdown reaching its end is the one thing the file watch
                // will never announce, so re-evaluate as it ticks.
                self.apply(ActivitiesReader.read())
                // And how hard a standing request presses is worked out from
                // this clock, by the island, while it draws. The island is not
                // watching this clock — it watches which features are live, and
                // this one has been live the whole time it has been waiting —
                // so without this the line it traces would keep the urgency it
                // had at the moment the request arrived, which is none.
                self.presence?.changed("activities")
            }
            self.clock = clock
            clock.start()
        } else if !needsClock, clock != nil {
            clock?.stop()
            clock = nil
        }
    }

    /// Wake exactly once, when the soonest notice is due to leave — something
    /// measured in seconds cannot wait for a tick that may not be running.
    private func scheduleNextDismissal(from moment: Date) {
        dismissalWork?.cancel()
        dismissalWork = nil

        let preferred = settings?.alerts.noticeSeconds
        let due = activities.compactMap { activity -> Date? in
            guard let seen = firstSeen[activity.id]?.at else { return nil }
            return activity.dismissalDate(firstSeen: seen, preferring: preferred)
        }
        guard let soonest = due.min() else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        dismissalWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.05, soonest.timeIntervalSince(moment)),
            execute: work
        )
    }
}
