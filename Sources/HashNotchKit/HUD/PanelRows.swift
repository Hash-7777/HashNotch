import AppKit
import SwiftUI

/// The panel's rows, as tall as they are — or, when that is taller than the
/// room below the notch, exactly that tall and scrolling.
///
/// The window was already capped at the room below the island, but the rows
/// inside it were not, so with enough indicators switched on the panel laid
/// itself out past the bottom of the screen and the window cut it off: the
/// last rows could not be reached at all.
///
/// The rows are always inside one scroll view, sized to them: exactly as tall
/// as the rows when they fit, with scrolling switched off and no fade, and
/// exactly as tall as the room when they do not.
///
/// It used to be two copies of the rows — a plain one, and a scrolling one
/// swapped in when the rows would not fit. A swap is a new set of views, and it
/// happened in the middle of whatever animation had changed the height. Stopping
/// a focus stretch did it every time on a full panel: the timer came out, the
/// rows fitted again, the plain copy took over, and its rows flew in from
/// where they had last been laid out, landing on top of one another before
/// they settled. One scroll view that only changes size has nothing to swap, so
/// every row is the same row before, during and after, and simply moves.
package struct PanelRows<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    /// The rows' own height, measured, which is what decides whether they
    /// scroll. The scroll view's size does not wait for it — `CappedHeight`
    /// sizes it in the same pass — so a frame behind costs nothing.
    @State private var rowsHeight: CGFloat = 0

    package init(maxHeight: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.maxHeight = maxHeight
        self.content = content
    }

    /// How much of the bottom of a scrolling panel fades out — a hint that
    /// there is more below. The rows gain the same amount of room
    /// at their end so the last one can scroll clear of it.
    static var fade: CGFloat { 14 }

    /// Whether the rows are taller than the room. Half a point of slack, so
    /// rows that fit exactly are not tipped into scrolling by rounding.
    private var scrolls: Bool { rowsHeight > maxHeight + 0.5 }

    package var body: some View {
        if #available(macOS 13.0, *) {
            CappedHeight(maxHeight: maxHeight) { scrollView }
        } else {
            // macOS 12 has no custom layouts, so the height is taken from the
            // rows themselves, measured, rather than asked of a layout.
            //
            // It used to be `frame(maxHeight:)` and a clip, and that is not the
            // same thing at all: a frame with only a maximum takes everything
            // it is offered up to that maximum, so EVERY panel on Monterey was
            // drawn the full height of the room with the rows at the top and a
            // tall black emptiness below them — and a long one was cut off with
            // no way to reach the rest. A measured height hugs the rows and
            // caps them at the room, which is what every later system gets, and
            // the scroll view then reaches what does not fit.
            scrollView
                .frame(height: PanelSize.height(rows: rowsHeight, room: maxHeight), alignment: .top)
        }
    }



    /// The rows, in a scroll view with no scroll bar.
    ///
    /// A bar is a column of its own. With "Show scroll bars: Always" set in
    /// System Settings — and whenever a mouse is connected, which is macOS's
    /// default for that setting — it is drawn inside the panel beside the rows,
    /// takes their room and pushes them sideways, and a panel built to look like
    /// part of the hardware grows a grey gutter down one side. `.never` holds
    /// whatever that setting says. The fade at the bottom is what says there is
    /// more, and the two-finger scroll is what reaches it.
    ///
    /// Rows that fit cannot be scrolled at all. The scroll view is exactly their
    /// height, so there is nowhere to go, and switching it off also stops the
    /// trackpad's rubber band from pulling a panel that fits away from its
    /// edges.
    ///
    /// The panel is built afresh each time it opens, so the scroll view starts
    /// at the top — and the opening then moved it. The panel drops in with a
    /// springy stretch, and that animation left the scroll view a few points
    /// down its own list (measured: 2.5 points, every time, before the settle
    /// wobble), so the top of the first row opened cut off. `TopHold` keeps it
    /// at the top until the opening has settled.
    private var scrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { rowsHeight = geo.size.height }
                        .onChange(of: geo.size.height) { rowsHeight = $0 }
                })
                .padding(.bottom, scrolls ? Self.fade : 0)
                .background(alignment: .top) { TopHold().frame(height: 0) }
        }
        .hidesScrollBar()
        .scrollHeld(!scrolls)
        // The fade is a mask on the scroll view itself. A gradient overlay was
        // tried in its place and did not show in use, and timing the two gave
        // the same cost per scroll step, so the mask, which does show, stays.
        // Rows that fit keep the mask with nothing faded, rather than losing
        // it, so the view is never rebuilt around them.
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, scrolls ? .clear : .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
            }
        )
    }
}

/// The height a panel takes where it has to be worked out rather than laid out.
///
/// Its own type rather than a member of `PanelRows`, which is generic over what
/// it holds: a rule nobody can call without naming a view type is a rule the
/// checks cannot reach.
package enum PanelSize {
    /// The rows' own height, held to the room — and nothing at all until they
    /// have been measured, so the first frame is drawn at the rows' height
    /// rather than at the room's.
    package static func height(rows: CGFloat, room: CGFloat) -> CGFloat? {
        guard rows > 0 else { return nil }
        return min(rows, room)
    }
}

/// Sizes its one child — the rows' scroll view — to the child's own height,
/// never taller than `maxHeight`.
///
/// A scroll view on its own takes every point it is offered, and nothing above
/// the panel has a height to offer it, so it has to be told. Its ideal height
/// is the height of what it holds, so asking for that and holding it to the
/// room gives rows that fit their own height and rows that do not the room.
@available(macOS 13.0, *)
package struct CappedHeight: Layout {
    let maxHeight: CGFloat

    package init(maxHeight: CGFloat) { self.maxHeight = maxHeight }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: min(size.height, maxHeight))
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

/// Holds a freshly opened scroll view at its top while the panel's opening
/// animation settles.
///
/// It only ever undoes a drift — a scroll position within `drift` points of
/// the top. Anything further is somebody scrolling, and a panel that fought a
/// finger to stay at the top would be worse than the drift it prevents.
///
/// A small scroll is not further, though, and that was the flaw: the panel's
/// scrolling is deliberately calmed to half distance, so an unhurried swipe in
/// the first second moves the list by less than the drift allowance and was
/// put straight back. For that second the panel appeared to refuse to scroll.
/// So the hold also ends the moment a scroll actually reaches the panel —
/// which the window controller knows, because every scroll over the panel
/// passes through it. See `PanelHold`.
package struct TopHold: NSViewRepresentable {
    /// Long enough for the opening spring and its settle to finish.
    package static let window: TimeInterval = 1.2
    package static let drift: CGFloat = 12

    package func makeNSView(context: Context) -> NSView { HoldView() }
    package func updateNSView(_ nsView: NSView, context: Context) {}

    final class HoldView: NSView {
        /// When this panel appeared, so a scroll from before it opened — the
        /// swipe that opened it, say — is not mistaken for one inside it.
        private var appearedAt = Date()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            appearedAt = Date()
            for delay in stride(from: 0.03, through: TopHold.window, by: 0.03) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.holdAtTop()
                }
            }
        }

        private func holdAtTop() {
            guard PanelHold.holds(appearedAt: appearedAt) else { return }
            guard let scroll = enclosingScrollView else { return }
            let y = scroll.contentView.bounds.origin.y
            guard y != 0, abs(y) <= TopHold.drift else { return }
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

/// Whether a freshly opened panel is still holding itself at its first row.
///
/// The rule is here, as a function of three moments, rather than inside the
/// view: when the panel appeared, when the list was last scrolled, and now.
@MainActor
package enum PanelHold {
    /// When a scroll last reached the panel. Set by the window controller,
    /// which sees every one of them.
    private(set) static var lastScroll: Date = .distantPast

    /// Told that somebody has scrolled the panel.
    package static func userScrolled(at moment: Date = Date()) {
        lastScroll = moment
    }

    /// Whether the drift correction still applies: inside the opening window,
    /// and nobody has scrolled since this panel appeared.
    /// `lastScroll` is the one the checks vary; left out, it is the real one.
    package static func holds(
        appearedAt: Date,
        now: Date = Date(),
        lastScroll: Date? = nil
    ) -> Bool {
        let scrolled = lastScroll ?? Self.lastScroll
        return now.timeIntervalSince(appearedAt) <= TopHold.window && scrolled < appearedAt
    }

    /// Used only by the checks, so one that scrolls does not change the answer
    /// for every check after it. The app never unlearns a scroll — a panel
    /// that has been scrolled is simply a panel somebody is using.
    package static func forgetLastScroll() {
        lastScroll = .distantPast
    }
}

/// How far the panel's rows move for a swipe.
///
/// macOS scrolls every view by the distance the fingers travelled, with
/// momentum after. That is right for a document hundreds of rows long; in a
/// panel that is only a few rows taller than the screen allows, an ordinary
/// flick carried the list to its end before the eye could follow it. Over the
/// panel the distance is scaled down — the same gesture, the same momentum and
/// the same rhythm, over less ground — so the list glides rather than jumps.
package enum PanelScroll {
    package static let factor: Double = 0.5

    /// The event with its vertical distance scaled by `factor`. Every field
    /// macOS reads a scroll's distance from is scaled together, so a trackpad,
    /// a mouse wheel and the momentum after a flick all slow alike; the phase
    /// fields are untouched, so a flick still coasts and settles.
    ///
    /// The order the fields are written in matters. They are linked: writing
    /// the line count recalculates the point distance from it, so writing
    /// points first and lines after quietly undid the scaling (a 10-point step
    /// came out as 8, not 5). Lines, then the fine-grained value, then points
    /// last leaves each where it was put.
    package static func calmed(_ event: NSEvent) -> NSEvent {
        guard let source = event.cgEvent, let copy = source.copy() else { return event }
        let lines = source.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        if lines != 0 {
            // A wheel's click is one line; halving it must not round to none.
            copy.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                      value: Int64((Double(lines) * factor).rounded(.awayFromZero)))
        }
        let fixed = source.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        copy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed * factor)
        let point = Double(source.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        copy.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64((point * factor).rounded()))
        return NSEvent(cgEvent: copy) ?? event
    }
}
