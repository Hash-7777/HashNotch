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
    /// there is more below. The rows gain the same amount of room at their end
    /// so the last one can scroll clear of it.
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

    private var scrolling: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .padding(.bottom, Self.fade)
        }
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
