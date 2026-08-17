import AppKit
import SwiftUI
import HashNotchKit

/// A simple countdown the user starts from the panel. While running it is a
/// live activity (compact countdown flanking the notch); when it ends it
/// chimes, posts a notification banner, and shows "Time's up" briefly.
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

    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var finishWork: DispatchWorkItem?
    private let notifier = TimerNotifier()

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        finishWork?.cancel()
        finishWork = nil
        phase = .idle
        presence?.setActive("timer", false)
    }

    // MARK: User actions

    public func begin(minutes: Int) {
        finishWork?.cancel()
        // Ask for notification permission now so the banner is ready to show
        // the instant the timer ends.
        notifier.requestAuthorization()
        let total = TimeInterval(minutes * 60)
        phase = .running(endsAt: Date().addingTimeInterval(total), total: total)
        presence?.setActive("timer", true)
        sampler = PollingSampler(interval: 1.0) { [weak self] in self?.tick() }
        sampler?.start()
    }

    public func cancel() {
        sampler?.stop()
        sampler = nil
        finishWork?.cancel()
        phase = .idle
        presence?.setActive("timer", false)
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

    private func tick() {
        now = Date()
        guard case .running(let endsAt, _) = phase else { return }
        if endsAt.timeIntervalSince(now) <= 0 {
            finish()
        }
    }

    private func finish() {
        sampler?.stop()
        sampler = nil
        phase = .finished
        notifier.fire(title: "Timer finished", body: "Your HashNotch timer is done.")

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
