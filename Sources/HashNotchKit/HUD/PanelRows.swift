import AppKit
import SwiftUI

/// The panel's rows, as tall as they are — or, when that is taller than the
/// room below the notch, exactly that tall and scrolling.
///
/// The window was already capped at the room below the island, but the rows
/// inside it were not, so with enough indicators switched on the panel laid
/// itself out past the bottom of the screen and the window cut it off: the
/// last rows could not be reached at all. This asks the rows how tall they
/// want to be against the room there is, and only when they will not fit does
/// it put them in a scroll view. A panel that fits is drawn exactly as before,
/// with nothing to scroll and no scroll bar.
package struct PanelRows<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    package init(maxHeight: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.maxHeight = maxHeight
        self.content = content
    }

    /// How much of the bottom of a scrolling panel fades out — a hint that
    /// there is more below. The rows gain the same amount of room
    /// at their end so the last one can scroll clear of it.
    static var fade: CGFloat { 14 }

    package var body: some View {
        if #available(macOS 13.0, *) {
            CappedHeight(maxHeight: maxHeight) {
                ViewThatFits(in: .vertical) {
                    content()
                    scrolling
                }
            }
        } else {
            // macOS 12 has neither ViewThatFits nor custom layouts, so the rows
            // are held to the room and anything past it is cut rather than
            // drawn off the screen. Every system since scrolls instead.
            content()
                .frame(maxHeight: maxHeight, alignment: .top)
                .clipped()
        }
    }

    /// The rows, scrolling, with no scroll bar.
    ///
    /// A bar is a column of its own. With "Show scroll bars: Always" set in
    /// System Settings — and whenever a mouse is connected, which is macOS's
    /// default for that setting — it is drawn inside the panel beside the rows,
    /// takes their room and pushes them sideways, and a panel built to look like
    /// part of the hardware grows a grey gutter down one side. `.never` holds
    /// whatever that setting says. The fade at the bottom is what says there is
    /// more, and the two-finger scroll is what reaches it.
    ///
    /// The panel is built afresh each time it opens, so the scroll view starts
    /// at the top — and the opening then moved it. The panel drops in with a
    /// springy stretch, and that animation left the scroll view a few points
    /// down its own list (measured: 2.5 points, every time, before the settle
    /// wobble), so the top of the first row opened cut off. `TopHold` keeps it
    /// at the top until the opening has settled.
    @available(macOS 13.0, *)
    private var scrolling: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .padding(.bottom, Self.fade)
                .background(alignment: .top) { TopHold().frame(height: 0) }
        }
        .scrollIndicators(.never)
        // The fade is a mask on the scroll view itself. A gradient overlay was
        // tried in its place and did not show in use, and timing the two gave
        // the same cost per scroll step, so the mask, which does show, stays.
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
            }
        )
    }
}

/// Proposes exactly `maxHeight` to its one child and sizes itself to whatever
/// the child then chooses, never taller.
///
/// This is what makes `ViewThatFits` able to answer at all. Left to itself the
/// panel is asked for its IDEAL height — nothing above it has a height to
/// offer — and against an unlimited height everything fits, so the first,
/// non-scrolling choice would win every time. Given the room as a real
/// proposal, the rows either fit it or they do not.
@available(macOS 13.0, *)
package struct CappedHeight: Layout {
    let maxHeight: CGFloat

    package init(maxHeight: CGFloat) { self.maxHeight = maxHeight }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: maxHeight))
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
