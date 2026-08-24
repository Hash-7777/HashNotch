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

    /// Set the length by turning a wheel, then start.
    ///
    /// It was a minus button, a figure and a plus button. Two problems with
    /// that, and the owner asked for the phone's answer instead: a press is one
    /// step, so any length far from where you started is a lot of presses, and
    /// the steps had to grow coarser as the number grew to keep that bearable —
    /// which meant the control silently changed what it did depending on where
    /// it already was.
    ///
    /// A wheel has neither problem. Every minute is one minute wherever you
    /// are, a slow drag picks one exactly, and a flick carries — so twelve
    /// minutes and two hours are the same gesture at different speeds.
    private var customRow: some View {
        HStack(spacing: 10) {
            TimerWheel(minutes: $engine.preferredMinutes, theme: theme)
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


/// A wheel of minutes, lying on its side.
///
/// Drawn rather than assembled from a system control, because macOS has no
/// wheel: `Picker` offers a menu or a list of radio buttons here, and neither is
/// something you can flick. What it imitates is the one on a phone, and that is
/// worth imitating for a reason that is not nostalgia — numbers moving under a
/// fixed mark tell you which way you are going and how fast, and a stepper's
/// single figure tells you neither.
///
/// The arithmetic is not in here. `TimerLength` turns a distance into a number
/// of minutes and back, so the part that can be wrong can also be measured.
struct TimerWheel: View {
    @Binding var minutes: Int
    let theme: Theme

    /// How far the current drag has travelled. Zero when nothing is being
    /// dragged, and the committed value in `minutes` is the truth.
    @State private var travelled: CGFloat = 0
    @State private var dragging = false

    /// Wide enough for a few minutes either side of the middle at the family's
    /// spacing, and narrow enough to leave the Start button its room.
    private static let width: CGFloat = 168
    private static let height: CGFloat = 26
    /// How many numbers are drawn each side. More than can be seen, so a number
    /// is never seen arriving from nowhere.
    private static let reach = 4

    /// What the wheel currently reads, which during a drag is not yet what has
    /// been committed.
    private var showing: Int { TimerLength.dragged(from: minutes, by: travelled) }

    var body: some View {
        ZStack {
            band
            numbers
        }
        .frame(width: Self.width, height: Self.height)
        // The numbers run out at the edges rather than stopping dead, so the
        // wheel reads as longer than the window it is seen through.
        .mask(fade)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityLabel("Timer length")
        .accessibilityValue("\(minutes) minutes")
        // Still adjustable without dragging, for anybody who would rather not
        // and for anybody who cannot.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = TimerLength.adjusted(minutes, by: 1)
            case .decrement: minutes = TimerLength.adjusted(minutes, by: -1)
            @unknown default: break
            }
        }
        .help("Drag the wheel, or press the number you want")
    }

    /// The band the chosen number sits in.
    ///
    /// It was two thin uprights either side, and they were the wrong shape for
    /// the job: at three digits the numbers grew until they touched them, so the
    /// thing marking the middle became a thing crowding it. A band sits BEHIND
    /// the number instead of beside it, so it cannot be crowded however wide the
    /// number is — which is how the wheels on a phone mark their middle, for the
    /// same reason.
    private var band: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.09))
            // Two points wider than the step between numbers, and no more: any
            // wider and the band's own edges start biting into the numbers
            // either side of the one it is marking, which at three digits are
            // already close.
            .frame(width: TimerLength.pointsPerMinute + 2, height: Self.height - 6)
    }

    private var numbers: some View {
        let centre = showing
        let residual = TimerLength.residual(travelled)
        return ZStack {
            ForEach(window(around: centre), id: \.self) { value in
                number(value, centre: centre, residual: residual)
            }
        }
        // Nothing animates while a finger is on it: the finger is already the
        // motion, and animating on top of it is what makes a wheel feel like it
        // is arguing with you.
        .animation(dragging ? nil : .snappy(duration: 0.22), value: centre)
    }

    /// The numbers worth drawing: more than fit, so none is ever seen arriving
    /// from nowhere, and never any that do not exist.
    private func window(around centre: Int) -> [Int] {
        let lowest = max(TimerLength.shortest, centre - Self.reach)
        let highest = min(TimerLength.longest, centre + Self.reach)
        guard lowest <= highest else { return [centre] }
        return Array(lowest...highest)
    }

    /// One number on the wheel. Written out with its parts named rather than as
    /// one expression — the compiler gave up type-checking the nested version,
    /// which is its way of saying the same thing a reader would.
    ///
    /// **Every number is the same size.** The middle one used to be drawn half
    /// again as large, and the wheel it made was not the one on a phone: the
    /// numbers had to be pushed far apart to leave room for it, and a strip of
    /// widely spaced numbers of differing sizes reads as a row of separate
    /// labels rather than as one turning thing. What marks the middle is where
    /// it is — in the band — and how bright it is, and those are enough. Only
    /// the fading is left to say which way the wheel runs.
    @ViewBuilder
    private func number(_ value: Int, centre: Int, residual: CGFloat) -> some View {
        let isCentre: Bool = value == centre
        let distance: CGFloat = CGFloat(value - centre)
        let weight: Font.Weight = isCentre ? .semibold : .medium
        let fade: Double = isCentre ? 1 : max(0.16, 0.5 - Double(abs(distance)) * 0.11)
        let slide: CGFloat = distance * TimerLength.pointsPerMinute + residual
        Text(String(value))
            .font(.system(size: 12, weight: weight, design: .rounded))
            .foregroundStyle(isCentre ? theme.textColor : theme.subtitleColor)
            .monospacedDigit()
            .opacity(fade)
            .offset(x: slide)
    }

    /// Solid in the middle, gone at both ends.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    /// How far a finger may move and still have been a press rather than a drag.
    private static let pressSlop: CGFloat = 3

    private var drag: some Gesture {
        // From nothing, so the same gesture sees a press. Two gestures on one
        // view would have to argue about which of them a short movement
        // belonged to, and the answer is knowable at the end: a press is a drag
        // that went nowhere.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard abs(value.translation.width) > Self.pressSlop else { return }
                dragging = true
                travelled = value.translation.width
            }
            .onEnded { value in
                // A press: go to the number under it.
                guard abs(value.translation.width) > Self.pressSlop else {
                    dragging = false
                    travelled = 0
                    let pressed = TimerLength.tapped(
                        from: minutes, atX: value.location.x, width: Self.width)
                    withAnimation(.snappy(duration: 0.24)) { minutes = pressed }
                    return
                }
                // Otherwise, where the finger was still going when it let go,
                // not where it stopped. Without this, every long timer is a
                // series of short drags.
                let thrown = value.predictedEndTranslation.width * TimerLength.flickThrow
                let carried = abs(thrown) > abs(value.translation.width)
                    ? thrown : value.translation.width
                let settled = TimerLength.dragged(from: minutes, by: carried)
                dragging = false
                travelled = 0
                withAnimation(.snappy(duration: 0.28)) { minutes = settled }
            }
    }
}
