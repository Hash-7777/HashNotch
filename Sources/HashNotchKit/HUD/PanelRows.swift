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
    /// Whether the panel is open. Each time it closes, the rows go back to the
    /// top, so the next opening starts at the first row rather than wherever
    /// the last one was left.
    let isOpen: Bool
    @ViewBuilder let content: () -> Content

    package init(maxHeight: CGFloat, isOpen: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.maxHeight = maxHeight
        self.isOpen = isOpen
        self.content = content
    }

    private static var topID: String { "panel-rows-top" }

    /// How much of the bottom of a scrolling panel fades to the panel's black —
    /// a hint that there is more below. The rows gain the same amount of room
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
    /// The panel's view outlives each opening, so a scroll position would carry
    /// over and a panel could open halfway down its own list. It is reset when
    /// the panel CLOSES rather than when it opens: done then, the jump happens
    /// while nothing is on screen, and the opening itself never moves.
    @available(macOS 13.0, *)
    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topID)
                    content()
                        .padding(.bottom, Self.fade)
                }
            }
            .scrollIndicators(.never)
            .onChange(of: isOpen) { open in
                if !open { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
        // The fade is a thin gradient laid OVER the bottom of the rows, not a
        // mask cut out of them. A mask makes every frame of scrolling render the
        // whole list offscreen before it can be composited — the scroll view
        // paying that on each step of a flick is what turns smooth into
        // stepping. An overlay is one small layer that never changes.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
                .allowsHitTesting(false)
        }
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
