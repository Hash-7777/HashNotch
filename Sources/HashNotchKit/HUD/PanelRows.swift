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
            // macOS 12 has no custom layouts, so the rows are held to the room
            // and anything past it is cut rather than drawn off the screen.
            // Every system since scrolls instead.
            content()
                .frame(maxHeight: maxHeight, alignment: .top)
                .clipped()
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
    @available(macOS 13.0, *)
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
        .scrollIndicators(.never)
        .scrollDisabled(!scrolls)
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
package struct TopHold: NSViewRepresentable {
    /// Long enough for the opening spring and its settle to finish.
    package static let window: TimeInterval = 1.2
    package static let drift: CGFloat = 12

    package func makeNSView(context: Context) -> NSView { HoldView() }
    package func updateNSView(_ nsView: NSView, context: Context) {}

    final class HoldView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            for delay in stride(from: 0.03, through: TopHold.window, by: 0.03) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.holdAtTop()
                }
            }
        }

        private func holdAtTop() {
            guard let scroll = enclosingScrollView else { return }
            let y = scroll.contentView.bounds.origin.y
            guard y != 0, abs(y) <= TopHold.drift else { return }
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
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
