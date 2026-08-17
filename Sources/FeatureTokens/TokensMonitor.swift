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

    private var sampler: VisibleSampler?
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

    public func start(
        visibility: PanelVisibility,
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
        sampler = VisibleSampler(interval: seconds * scale, visibility: visibility) { [weak self] in
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
