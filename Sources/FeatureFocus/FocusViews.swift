import SwiftUI
import HashNotchKit

/// Compact-live: which part of the cycle is running, left of the notch.
struct FocusIconView: View {
    @ObservedObject var engine: FocusEngine
    let theme: Theme

    var body: some View {
        if let session = engine.session {
            FocusRing(
                fraction: session.fractionDone(now: engine.now),
                tint: session.block.isWork ? theme.accent : FocusPalette.rest,
                lineWidth: 2.5
            )
            .frame(width: 16, height: 16)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
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

/// A ring that fills as a block is served.
///
/// A ring rather than a bar for the one that sits beside the notch: a bar has to
/// be wide to be read and the strip has no width to spare, while a ring says the
/// same thing in a square. It is drawn from the top and clockwise, because that
/// is the direction every clock anybody has looked at goes.
struct FocusRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Expanded: the cycle, and what the day came to.
struct FocusDetailView: View {
    @ObservedObject var engine: FocusEngine
    @ObservedObject var settings: SettingsStore
    let theme: Theme

    /// Everything here is scaled by the Motion setting and by what this macOS
    /// can draw in time, like every other animation in the app. A page that
    /// ignored Motion would be the one place in it that did.
    private var motion: Double {
        settings.appearance.motion.responseScale * SystemGeneration.current.motionScale
    }

    private var tint: Color {
        guard let session = engine.session else { return theme.accent }
        return session.block.isWork ? theme.accent : FocusPalette.rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotchSectionHeader("FOCUS", icon: .focus, theme: theme)

            if let session = engine.session {
                running(session)
            } else {
                idle
            }

            if !engine.tally.isEmpty || !engine.history.isEmpty {
                Divider().overlay(theme.subtitleColor.opacity(0.22))
                today
            }
        }
        .frame(width: Panel.rowWidth, alignment: .leading)
        .animation(.spring(response: 0.42 * motion, dampingFraction: 0.86), value: engine.session?.block)
        .animation(.spring(response: 0.5 * motion, dampingFraction: 0.8), value: engine.tally.finishedWork)
    }

    // MARK: While a block runs

    private func running(_ session: FocusSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                FocusRing(fraction: session.fractionDone(now: engine.now), tint: tint)
                    .frame(width: 46, height: 46)
                    // The ring is redrawn every second, so it must ease over
                    // exactly one second or it arrives in steps you can see.
                    .animation(.linear(duration: 1), value: session.fractionDone(now: engine.now))
                Image(systemName: session.block.isWork ? "target" : "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .id(session.block)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(FocusClock.text(session.secondsLeft(now: engine.now)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
                Text(session.block.isWork
                     ? "\(engine.plan.worksUntilLongBreak(finishedWorkBlocks: engine.tally.finishedWork)) more rounds until a long rest"
                     : "Then back to work")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
            }

            Spacer(minLength: 0)

            VStack(spacing: 5) {
                FocusButton("Skip", theme: theme) { engine.skip() }
                FocusButton("Stop", theme: theme) { engine.giveUp() }
            }
        }
        .transition(.opacity.combined(with: .offset(y: -4)))
    }

    // MARK: While nothing runs

    private var idle: some View {
        HStack(spacing: 10) {
            FocusButton("Start \(engine.plan.workMinutes) min", theme: theme, filled: true) {
                engine.begin(.work)
            }
            if engine.alertsAllowed == false {
                // Never promise what will not happen.
                Text("Notifications are off. It will chime instead.")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .offset(y: 4)))
    }

    // MARK: The day

    private var today: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
                Spacer(minLength: 8)
                // The noun is the point. "1 hr 15 min" on its own is a number
                // somebody has to guess the meaning of.
                Text(FocusTallyMath.focusedText(engine.tally.workSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textColor)
            }

            if engine.tally.finishedWork > 0 {
                HStack(spacing: 7) {
                    FocusRoundDots(done: engine.tally.finishedWork, tint: theme.accent, motion: motion)
                    // What the marks ARE. Without this they are decoration that
                    // somebody counts and then wonders about.
                    Text(FocusTallyMath.roundsText(engine.tally.finishedWork))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                    Spacer(minLength: 0)
                }
            }

            if let average = FocusHistoryMath.averageText(engine.history) {
                Text(average)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
            }
            if engine.tally.abandonedWork > 0 {
                Text(FocusTallyMath.stoppedText(engine.tally.abandonedWork))
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
            }
        }
        .transition(.opacity)
    }
}

/// One mark per round finished.
///
/// Only the rounds that happened. It used to draw empty ones as well, scaled to
/// the busiest day kept — which read as "3 of 6 done" against a target of six
/// that did not exist anywhere. A row that grows as the day goes says the same
/// thing and invents nothing.
struct FocusRoundDots: View {
    let done: Int
    let tint: Color
    let motion: Double

    /// A cap, so a very long day cannot push the row past the panel. Past this
    /// the count beside it carries the number.
    private static let mostDrawn = 10

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(done, Self.mostDrawn), id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    // Each lands a beat after the one before, so a row arriving
                    // at once reads as a row rather than a flash.
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .animation(
                        .spring(response: 0.34 * motion, dampingFraction: 0.62)
                            .delay(Double(index) * 0.02 * motion),
                        value: done
                    )
            }
            if done > Self.mostDrawn {
                Text("+\(done - Self.mostDrawn)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

struct FocusButton: View {
    let title: String
    let theme: Theme
    var filled: Bool = false
    let action: () -> Void
    @State private var hovered = false

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
                    Capsule().fill(
                        filled
                            ? theme.accent.opacity(hovered ? 0.85 : 1)
                            : Color.white.opacity(hovered ? 0.18 : 0.10)
                    )
                )
                .foregroundStyle(filled ? theme.onAccent : theme.textColor)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
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
