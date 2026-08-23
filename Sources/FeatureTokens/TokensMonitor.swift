import Foundation
import SwiftUI
import HashNotchKit

/// Publishes today's AI token usage.
///
/// Three things keep this cheap. The count itself only reads what has been
/// appended since the last one (`TokenUsageScanner`). The last answer is
/// remembered across launches (`TokenTotalsCache`), so the panel opens on a
/// number instead of on a zero it has not earned. And how often it counts at all
/// is the reader's choice, down to not counting on a clock at all.
///
/// The scan runs on a background queue; results are published on the main actor
/// inside an animation so the numbers roll rather than jump.
@MainActor
public final class TokensMonitor: ObservableObject {
    @Published public private(set) var today = TokenTotals()
    /// When these totals were counted — from this run, or remembered from the
    /// last one. Nil means they have never been counted, which is a different
    /// thing from counting zero and is shown differently.
    @Published public private(set) var countedAt: Date?
    /// Whether a count is running right now.
    @Published public private(set) var isCounting = false

    private var sampler: PollingSampler?
    private let queue = DispatchQueue(label: "com.hashnotch.tokens", qos: .utility)
    private let scanner = TokenUsageScanner()
    private let defaults: UserDefaults
    private var inFlight = false

    /// `defaults` is a parameter purely so the checks can exercise the remembered
    /// totals without touching the real preferences.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let remembered = TokenTotalsCache.load(from: defaults) {
            today = remembered.totals
            countedAt = remembered.countedAt
        }
    }

    /// Takes no `PanelVisibility`, unlike most readers here, and deliberately:
    /// this one is not allowed to depend on whether anybody is looking.
    public func start(
        scale: Double = 1,
        interval: TokenScanInterval = .fiveMinutes
    ) {
        guard let seconds = interval.seconds else {
            // "Only when I ask" is taken at its word: nothing is read until the
            // refresh control is used. Counting once here would make the setting
            // mean "only when I ask, and also every time you launch", which is
            // not what it says.
            return
        }
        // A PLAIN sampler, not a panel-gated one, and this is the whole point
        // of the setting above it.
        //
        // It used to be gated on the panel being open, which quietly made
        // "every minute" mean "every minute that you happen to be looking at
        // it". The strip shows a running total for TODAY: a figure that only
        // counted the moments somebody was watching is not that total, it is a
        // record of when the panel was open, and it would sit unchanged for
        // hours and then jump the instant it was looked at — which reads as a
        // number invented on demand rather than one being kept.
        //
        // The reading is cheap enough to keep on a clock: each file's read
        // position is remembered, so a count with nothing new to read opens
        // nothing at all and costs a directory listing. That is what makes an
        // honest interval affordable, and it is the same reasoning the data-used
        // total is kept on its own clock for.
        sampler = PollingSampler(interval: seconds * scale) { [weak self] in
            self?.refresh()
        }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    /// Count now, whatever the interval says. Behind the panel's refresh control.
    public func refreshNow() {
        refresh()
    }

    private func refresh() {
        guard !inFlight else { return }
        inFlight = true
        isCounting = true
        queue.async { [weak self] in
            guard let self else { return }
            let totals = self.scanner.readToday()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = false
                self.isCounting = false
                let now = Date()
                self.countedAt = now
                TokenTotalsCache.save(totals, now: now, to: self.defaults)
                guard totals != self.today else { return }
                withAnimation(.snappy) { self.today = totals }
            }
        }
    }
}
