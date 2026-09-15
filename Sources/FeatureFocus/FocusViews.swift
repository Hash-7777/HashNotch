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
        VStack(alignment: .leading, spacing: 8) {
            // One row, laid out the way every other row in the panel is: the
            // mark and the name on the left with the week as a quiet second
            // line under the name, and the one thing to press on the right.
            // Everything shares the left edge; nothing floats in the middle.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Self.markGap) {
                        // The same grey as every other row's name and mark, so
                        // this reads as one of the panel's rows, not a heading.
                        NotchIconView(.focus, size: Self.markSize, color: theme.subtitleColor)
                        Text("Focus")
                            .foregroundStyle(theme.subtitleColor)
                    }
                    if engine.session == nil {
                        weekLine
                    }
                }
                Spacer(minLength: 8)
                if engine.session == nil {
                    FocusStartButton(minutes: engine.plan.workMinutes, theme: theme) {
                        engine.begin(.work)
                    }
                    .transition(.opacity)
                }
            }

            if let session = engine.session {
                running(session)
                weekLine
            }

            if engine.session == nil, engine.alertsAllowed == false {
                // Never promise what will not happen.
                Text("Notifications are off. It will chime instead.")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
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
                     ? "Long rest after \(engine.plan.worksUntilLongBreak(finishedWorkBlocks: engine.tally.finishedWork)) more"
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

    /// One sentence, always there, saying the only thing worth saying: how
    /// much focus is behind you. No second section, no marks, and no word
    /// anybody has to be taught.
    ///
    /// One thin line, never two, starting under the word "Focus" rather than
    /// under its mark, so the name and its footnote read as one label.
    private var weekLine: some View {
        Text(FocusHistoryMath.weekText(engine.history, today: engine.tally))
            .font(.system(size: 9))
            // A step quieter than the name above it, so the two read as a
            // name and its footnote rather than as two labels.
            .foregroundStyle(theme.subtitleColor.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.leading, Self.markSize + Self.markGap)
    }

    /// The mark at the row's own text size, as every row in the panel draws it.
    private static let markSize: CGFloat = 11
    private static let markGap: CGFloat = 6

}

/// The one control of an idle focus section: start a stretch.
///
/// Tinted rather than filled — the accent at low strength behind the accent
/// itself, with a thin edge — the way the system draws a button that belongs to
/// a row rather than one that owns the screen. A solid block of colour was the
/// loudest thing in the panel for a control that is used a few times a day.
struct FocusStartButton: View {
    let minutes: Int
    let theme: Theme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7.5, weight: .bold))
                Text("\(minutes) min")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(Capsule().fill(theme.accent.opacity(hovered ? 0.26 : 0.16)))
            .overlay(Capsule().strokeBorder(theme.accent.opacity(0.32), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Start a \(minutes)-minute focus stretch")
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
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
