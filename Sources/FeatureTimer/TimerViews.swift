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
/// wheel: `Picker` offers a menu or a column of radio buttons here, and neither
/// is something anybody can flick. What it imitates is the one on a phone, and
/// that is worth imitating for a reason that is not nostalgia — numbers moving
/// under a fixed mark tell you which way you are going and how fast, and a
/// stepper's single figure tells you neither.
///
/// **One number holds its state.** `position` is where the strip is, measured
/// in minutes and fractional while it turns, and every number on the strip is
/// placed against it. That is the whole of the design, and it is a correction:
/// the first version kept the committed minute and the finger's travel
/// separately and worked out what to draw from the pair, which lurched on
/// release and scattered on a press. See `TimerLength.position(from:draggedBy:)`
/// for what those two faults looked like.
///
/// **Nothing fades by hand.** Every number is drawn at one size and one weight
/// apart from the one under the band, and the falling-away at the edges is a
/// mask over the whole strip rather than an opacity worked out per number. A
/// number therefore does not change as it travels — it is simply somewhere the
/// mask is thinner — which is why the strip reads as one moving object.
///
/// The arithmetic is not in here. `TimerLength` turns a drag or a press into a
/// position, so the part that can be wrong can also be measured.
struct TimerWheel: View {
    @Binding var minutes: Int
    let theme: Theme

    /// Where the strip is, in minutes. The only state the wheel has.
    @State private var position: CGFloat = CGFloat(TimerLength.initial)
    /// A position to open at instead of the one the binding carries.
    ///
    /// Only ever passed when the wheel is being drawn for inspection rather
    /// than used. A still picture of a wheel cannot show the one thing that
    /// matters about it — what a half-turned strip looks like — and this is how
    /// that picture gets taken.
    var startingAt: CGFloat?
    /// Where it was when the current turn began.
    @State private var anchor: CGFloat = CGFloat(TimerLength.initial)
    @State private var turning = false

    /// Wide enough for a few minutes either side of the middle, and narrow
    /// enough to leave the Start button its room.
    private static let width: CGFloat = 168
    private static let height: CGFloat = 26
    /// How many numbers are drawn each side. Well past the edge of the window,
    /// so a number is never seen arriving from nowhere — it is already drawn,
    /// out where the mask has taken it to nothing.
    private static let reach = 5
    /// How far a finger may move and still have been a press rather than a drag.
    private static let pressSlop: CGFloat = 3

    /// The minute the wheel is resting on, which during a turn is whichever one
    /// is passing under the band.
    private var showing: Int { TimerLength.settled(position) }

    var body: some View {
        ZStack {
            band
            strip
        }
        .frame(width: Self.width, height: Self.height)
        // The numbers run out at the edges rather than stopping dead, so the
        // wheel reads as longer than the window it is seen through — and this
        // is also what hides the ones drawn beyond it.
        .mask(fade)
        .contentShape(Rectangle())
        .gesture(turn)
        .onAppear { position = startingAt ?? CGFloat(minutes) }
        .accessibilityLabel("Timer length")
        .accessibilityValue("\(minutes) minutes")
        // Still adjustable without dragging, for anybody who would rather not
        // and for anybody who cannot.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(on: TimerLength.adjusted(minutes, by: 1))
            case .decrement: settle(on: TimerLength.adjusted(minutes, by: -1))
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

    private var strip: some View {
        let centre = showing
        return ZStack {
            ForEach(window(around: centre), id: \.self) { value in
                number(value, centre: centre)
            }
        }
    }

    /// The numbers worth drawing: more than fit, so none is ever seen arriving
    /// from nowhere, and never any that do not exist.
    private func window(around centre: Int) -> [Int] {
        let lowest = max(TimerLength.shortest, centre - Self.reach)
        let highest = min(TimerLength.longest, centre + Self.reach)
        guard lowest <= highest else { return [centre] }
        return Array(lowest...highest)
    }

    /// One number, placed against the strip's position rather than against the
    /// selected minute.
    ///
    /// That distinction is the whole fix. Measured against the selection, every
    /// number moved whenever the selection changed and SwiftUI animated each of
    /// them separately — a scatter. Measured against `position`, a number's
    /// place is fixed and the strip is what moves.
    ///
    /// Written out with its parts named rather than as one expression: the
    /// compiler gave up type-checking the nested version, which is its way of
    /// saying what a reader would.
    @ViewBuilder
    private func number(_ value: Int, centre: Int) -> some View {
        let isCentre: Bool = value == centre
        let weight: Font.Weight = isCentre ? .semibold : .medium
        let slide: CGFloat = (CGFloat(value) - position) * TimerLength.pointsPerMinute
        Text(String(value))
            .font(.system(size: 12, weight: weight, design: .rounded))
            .foregroundStyle(isCentre ? theme.textColor : theme.subtitleColor)
            .monospacedDigit()
            .offset(x: slide)
    }

    /// Solid in the middle, gone at both ends.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    private var turn: some Gesture {
        // From nothing, so the same gesture sees a press. Two gestures on one
        // view would have to argue about which of them a short movement
        // belonged to, and the answer is knowable at the end: a press is a turn
        // that went nowhere.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !turning {
                    turning = true
                    anchor = position
                }
                guard abs(value.translation.width) > Self.pressSlop else { return }
                position = TimerLength.position(from: anchor, draggedBy: value.translation.width)
            }
            .onEnded { value in
                turning = false
                guard abs(value.translation.width) > Self.pressSlop else {
                    settle(on: TimerLength.tapped(
                        from: showing, atX: value.location.x, width: Self.width))
                    return
                }
                // Where the finger was still going when it let go, not where it
                // stopped. Without this, every long timer is a series of short
                // drags.
                let thrown = value.predictedEndTranslation.width * TimerLength.flickThrow
                let carried = abs(thrown) > abs(value.translation.width)
                    ? thrown : value.translation.width
                settle(on: TimerLength.settled(
                    TimerLength.position(from: anchor, draggedBy: carried)))
            }
    }

    /// Come to rest on a minute: the strip glides there, and that minute is the
    /// answer.
    ///
    /// Both in one transaction, because they are one event. Setting them apart
    /// is what made the wheel lurch — for a frame the strip would be back where
    /// the turn started while the answer had already moved on.
    private func settle(on target: Int) {
        withAnimation(.snappy(duration: 0.26)) {
            position = CGFloat(target)
            minutes = target
        }
    }
}
