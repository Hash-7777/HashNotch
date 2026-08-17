import SwiftUI

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A single-line text that scrolls continuously when it does not fit — like
/// track titles on the iPhone. Short text renders as a plain label; long text
/// dwells briefly, glides left through a soft edge fade, and loops seamlessly.
///
/// Sizing works like `Text`: the view hugs short content and respects whatever
/// width cap the caller applies (`.frame(maxWidth:)`). Font and color are
/// inherited from the environment, so style it exactly like a `Text`.
///
/// Set `scrolls` to false to hold it still. A marquee is a 30-frames-a-second
/// animation that never ends on its own, so anything drawing one for something
/// that has stopped — a paused track keeping its place at the notch — should
/// say so, or the app pays for that animation for as long as the notch holds
/// the title. Held still, it returns to the start of the text rather than
/// freezing wherever the scroll happened to be.
public struct MarqueeText: View {
    private let text: String
    /// Whether the text is allowed to scroll. False holds it at the start.
    private let scrolls: Bool
    /// Scroll speed in points per second.
    private let speed: Double
    /// Gap between the end of the text and its looping copy.
    private let gap: CGFloat
    /// Pause at the start of every loop, in seconds.
    private let dwell: Double

    @State private var textWidth: CGFloat = 0
    /// The loop is anchored to when THIS text appeared — never to absolute
    /// time. With an absolute clock the marquee would materialize mid-cycle
    /// and visibly jump left the moment measurement landed.
    @State private var appeared = Date()

    public init(
        _ text: String,
        scrolls: Bool = true,
        speed: Double = 30,
        gap: CGFloat = 36,
        dwell: Double = 1.4
    ) {
        self.text = text
        self.scrolls = scrolls
        self.speed = speed
        self.gap = gap
        self.dwell = dwell
    }

    private var label: some View {
        Text(text).lineLimit(1)
    }

    public var body: some View {
        label
            .opacity(0) // reserves the height and (capped) width
            .overlay(alignment: .leading) { marquee }
            .background(
                // Measure the full, uncapped text width.
                label.fixedSize().hidden().background(
                    GeometryReader { geo in
                        Color.clear.preference(key: MarqueeTextWidthKey.self, value: geo.size.width)
                    }
                )
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
            // Resuming restarts the loop rather than rejoining it. The clock
            // runs on regardless of whether the text is scrolling, so without
            // this a title held still and then released would jump straight to
            // wherever the cycle had got to in the meantime.
            .onChange(of: scrolls) { isScrolling in
                if isScrolling { appeared = Date() }
            }
            .id(text) // new title → fresh measurement and loop
    }

    @ViewBuilder
    private var marquee: some View {
        GeometryReader { geo in
            let available = geo.size.width
            if textWidth > available + 1 {
                // `paused` stops the timeline entirely — no ticks, no layout,
                // no commit — rather than merely holding the offset still while
                // the clock keeps waking the view 30 times a second.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !scrolls)) { context in
                    let span = textWidth + gap
                    let cycle = dwell + Double(span) / speed
                    let t = scrolls
                        ? max(0, context.date.timeIntervalSince(appeared))
                            .truncatingRemainder(dividingBy: cycle)
                        : 0
                    let distance = CGFloat(max(0, t - dwell) * speed)
                    HStack(spacing: gap) {
                        label.fixedSize()
                        label.fixedSize()
                    }
                    .offset(x: -min(distance, span))
                    .animation(.easeOut(duration: 0.3), value: scrolls)
                    .frame(width: available, height: geo.size.height, alignment: .leading)
                    .clipped()
                    // The fade at the START is applied only once the text has
                    // actually begun to move.
                    //
                    // It exists to soften a glyph sliding out of view, and a
                    // title that is standing still has no glyph doing that —
                    // but the gradient did not know the difference, so the
                    // first letter of every title sat under a permanent wash of
                    // transparency. Against the black beside it that does not
                    // read as a soft edge, it reads as a smudge on the first
                    // letter: the one character the eye lands on first.
                    //
                    // The trailing fade is unconditional, because there is
                    // always more title out to the right than there is room
                    // for — that is why this view exists at all.
                    .mask(
                        LinearGradient(
                            stops: distance > 0.5
                                ? [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.035),
                                    .init(color: .black, location: 0.965),
                                    .init(color: .clear, location: 1),
                                ]
                                : [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.965),
                                    .init(color: .clear, location: 1),
                                ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            } else {
                label
            }
        }
    }
}
