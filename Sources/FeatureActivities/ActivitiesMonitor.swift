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

    /// When each self-dismissing notice was first seen, alongside the notice
    /// itself so a NEW one under a reused id is recognised as new. A notice says
    /// how long it wants to be shown for, not when it should go: the writer has
    /// no idea when the app will next look at the file.
    private var firstSeen: [String: (activity: LiveActivity, at: Date)] = [:]

    /// When this activity first arrived, for anything that wants to say how
    /// long it has been standing there rather than how long it has left.
    package func arrived(_ activity: LiveActivity) -> Date? { firstSeen[activity.id]?.at }

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
    private func refreshHookState() {
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

    /// Whether this notice is one whose few seconds have not started counting.
    ///
    /// True for a notice never seen before, and for one whose content differs
    /// from the last post under the same id — which is what a genuinely new
    /// alert looks like, since every post carries its own `endsAt`. False for a
    /// re-read of the same notice, so its clock keeps running from when it
    /// actually arrived rather than restarting on every glance at the file.
    ///
    /// Pure and package-visible: this is the decision that silently swallowed
    /// every repeat alert, so it is pinned by the checks rather than left to be
    /// re-derived by eye.
    package nonisolated static func startsFresh(
        _ activity: LiveActivity,
        previously: LiveActivity?
    ) -> Bool {
        guard activity.dismissAfter != nil else { return false }
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

        let preferred = settings?.alerts.noticeSeconds
        let showing = fresh.filter { activity in
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
