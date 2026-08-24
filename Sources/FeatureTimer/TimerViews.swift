import AppKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchSectionHeader("TIMER", icon: .timer, theme: theme)
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
            if engine.notificationsAllowed == false { refusedNotice }
        }
    }

    /// Said only when it is true, and only once a timer has actually asked.
    ///
    /// An app that has been refused notification permission and goes on looking
    /// exactly as it did is an app that has quietly stopped doing what it says.
    /// The alert still happens — it chimes instead — and the difference matters:
    /// a chime needs somebody within earshot of this Mac, and a banner waits.
    /// Saying which one you are getting is the whole of it.
    private var refusedNotice: some View {
        Button {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            ) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 8.5, weight: .bold))
                Text("Notifications are off — this will chime instead")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9))
            .foregroundStyle(theme.subtitleColor)
            .frame(width: Panel.rowWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open System Settings, where notifications for HashNotch can be turned back on")
    }

    /// Set your own length: minus / value / plus, then start.
    private var customRow: some View {
        HStack(spacing: 8) {
            stepButton("minus") {
                engine.preferredMinutes = TimerLength.adjusted(engine.preferredMinutes, by: -1)
            }
            Text("\(engine.preferredMinutes) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .frame(minWidth: 52)
            stepButton("plus") {
                engine.preferredMinutes = TimerLength.adjusted(engine.preferredMinutes, by: 1)
            }
            Spacer(minLength: 0)
            Button {
                engine.begin(minutes: engine.preferredMinutes)
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

package enum TimerViews {
    /// mm:ss (or h:mm:ss beyond an hour).
    package static func clock(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
