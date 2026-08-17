import SwiftUI
import HashNotchKit

/// Compact-live: a small timer glyph left of the notch while counting down.
struct TimerIconView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    var body: some View {
        switch engine.phase {
        case .running:
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
        case .finished:
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
        case .idle:
            EmptyView()
        }
    }
}

/// Compact-live: the countdown right of the notch.
struct TimerTextView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    var body: some View {
        switch engine.phase {
        case .running:
            Text(TimerViews.clock(engine.secondsLeft(now: engine.now)))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .finished:
            Text("Time's up")
                .foregroundStyle(theme.textColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .idle:
            EmptyView()
        }
    }
}

/// Expanded detail: quick-start buttons when idle; countdown, progress, and
/// a stop button while running.
struct TimerDetailView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    /// The user's own timer length, adjusted with the stepper.
    @State private var customMinutes = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchSectionHeader("TIMER", theme: theme)
            switch engine.phase {
            case .idle:
                // Just the one row. The 5/15/25 pills were three guesses at a
                // length nobody asked for, sitting above a control that can
                // already be any length in a couple of taps.
                customRow
                .frame(width: Panel.rowWidth)
            case .running:
                HStack(spacing: 10) {
                    Text(TimerViews.clock(engine.secondsLeft(now: engine.now)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.16))
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: max(3, geo.size.width * engine.fractionDone(now: engine.now)))
                        }
                    }
                    .frame(height: 3)
                    stopButton
                }
                .frame(width: Panel.rowWidth)
            case .finished:
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Time's up")
                        .foregroundStyle(theme.textColor)
                    Spacer(minLength: 0)
                    Button("OK") { engine.cancel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.subtitleColor)
                }
                .frame(width: Panel.rowWidth)
            }
        }
    }

    /// Set your own length: minus / value / plus, then start.
    private var customRow: some View {
        HStack(spacing: 8) {
            stepButton("minus") { customMinutes = max(1, customMinutes - step) }
            Text("\(customMinutes) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .frame(minWidth: 52)
            stepButton("plus") { customMinutes = min(600, customMinutes + step) }
            Spacer(minLength: 0)
            Button {
                engine.begin(minutes: customMinutes)
            } label: {
                // A timer glyph and the word, not a play triangle. The triangle
                // is the universal mark for "play this media", and sitting in a
                // panel whose other controls genuinely are media controls, it
                // read as one of them rather than as the thing that starts the
                // countdown.
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .bold))
                    Text("Start")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                // Not theme.textColor. This label sits ON the accent, and one
                // of the accents on offer is White — which made the button read
                // as an empty capsule.
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(theme.accent.opacity(0.9)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Coarser steps at higher values so long durations are quick to dial.
    private var step: Int { customMinutes >= 60 ? 15 : (customMinutes >= 20 ? 5 : 1) }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.textColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button {
            engine.cancel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.subtitleColor)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

enum TimerViews {
    /// mm:ss (or h:mm:ss beyond an hour).
    static func clock(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
