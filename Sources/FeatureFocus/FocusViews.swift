import SwiftUI
import HashNotchKit

/// Compact-live: which part of the cycle is running, left of the notch.
struct FocusIconView: View {
    @ObservedObject var engine: FocusEngine
    let theme: Theme

    var body: some View {
        if let session = engine.session {
            Image(systemName: session.block.isWork ? "target" : "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(session.block.isWork ? theme.accent : FocusPalette.rest)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Compact-live: what is running and how long is left, right of the notch.
struct FocusTitleView: View {
    @ObservedObject var engine: FocusEngine
    let theme: Theme

    var body: some View {
        if let session = engine.session {
            HStack(spacing: 6) {
                Text(session.block.label)
                    .foregroundStyle(theme.subtitleColor)
                Text(FocusClock.text(session.secondsLeft(now: engine.now)))
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
            }
            .fixedSize(horizontal: true, vertical: false)
            .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }
}

/// Expanded: the cycle, and what the day has come to.
struct FocusDetailView: View {
    @ObservedObject var engine: FocusEngine
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchSectionHeader("FOCUS", icon: .focus, theme: theme)

            if let session = engine.session {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.block.label)
                            .foregroundStyle(theme.textColor)
                        Text(session.block.isWork
                             ? "\(engine.plan.worksUntilLongBreak(finishedWorkBlocks: engine.tally.finishedWork)) to the long break"
                             : "Then back to it")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                    }
                    Spacer(minLength: 8)
                    Text(FocusClock.text(session.secondsLeft(now: engine.now)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                        .rollingDigits()
                }

                ProgressBar(
                    fraction: session.fractionDone(now: engine.now),
                    tint: session.block.isWork ? theme.accent : FocusPalette.rest
                )

                HStack(spacing: 8) {
                    FocusButton("Skip", theme: theme) { engine.skip() }
                    FocusButton("Stop", theme: theme) { engine.giveUp() }
                }
            } else {
                HStack(spacing: 8) {
                    FocusButton("Start \(engine.plan.workMinutes) min", theme: theme, filled: true) {
                        engine.begin(.work)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider().overlay(theme.subtitleColor.opacity(0.25))

            // The part that does not flatter you.
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
                Text(FocusTallyMath.summary(engine.tally))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textColor)
                if engine.tally.abandonedWork > 0 {
                    Text("\(engine.tally.abandonedWork) not finished")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                }
            }
        }
        .frame(width: Panel.rowWidth, alignment: .leading)
    }
}

/// A plain bar. The panel has one already for the disk, but that one is a
/// segmented picture of a filled thing; this is a fraction of a countdown.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

struct FocusButton: View {
    let title: String
    let theme: Theme
    var filled: Bool = false
    let action: () -> Void

    init(_ title: String, theme: Theme, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.theme = theme
        self.filled = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(filled ? theme.accent : Color.white.opacity(0.10))
                )
                .foregroundStyle(filled ? theme.onAccent : theme.textColor)
        }
        .buttonStyle(.plain)
    }
}

enum FocusPalette {
    /// A break is not the accent. The accent means work is running, and a rest
    /// that wore the same colour would make the one state you can see from
    /// across the room say nothing.
    static let rest = Color(red: 0.36, green: 0.72, blue: 0.94)
}

/// Minutes and seconds, and hours only when there are any.
package enum FocusClock {
    package static func text(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 3_600 { return String(format: "%d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}
