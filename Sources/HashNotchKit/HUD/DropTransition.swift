import SwiftUI

/// The transition that makes a shape look like it came out of the notch.
///
/// SwiftUI's built-in `.scale` is uniform: it shrinks a view toward a point,
/// which is why a panel using it appears to balloon out of nowhere rather than
/// grow from the hardware. A drop is not uniform. It starts at exactly the
/// notch's width and almost no height, then stretches downward and outward,
/// staying welded to the top edge the whole way — the same way a bead of water
/// swells before it falls.
///
/// The anchor matters as much as the ratios. Anchored to a view's own centre,
/// a shape converges to the middle of itself; the notch is rarely there. The
/// live strip in particular is deliberately lopsided, so it is given the notch's
/// actual position within it.
struct DropEffect: ViewModifier, Animatable {
    var widthRatio: CGFloat
    var heightRatio: CGFloat
    var fade: Double
    let anchor: UnitPoint

    /// Animating all three together keeps the stretch and the fade on one
    /// curve; separately they drift apart and the shape appears to flicker as
    /// it grows.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Double> {
        get { AnimatablePair(AnimatablePair(widthRatio, heightRatio), fade) }
        set {
            widthRatio = newValue.first.first
            heightRatio = newValue.first.second
            fade = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: widthRatio, y: heightRatio, anchor: anchor)
            .opacity(fade)
    }
}

extension AnyTransition {
    /// Emerge from — and retreat back into — the notch.
    ///
    /// `widthRatio` and `heightRatio` are where the shape begins, as fractions
    /// of its final size: pass the notch's width over the shape's width to have
    /// it start exactly as wide as the hardware.
    ///
    /// It leaves a little smaller than it arrived, so closing reads as being
    /// drawn back in rather than merely playing the opening backwards.
    /// `arrivesOpaque` skips the fade on the way IN, so the shape is at full
    /// strength from its first frame and only grows.
    ///
    /// Filmed in slow motion against a white desktop, fading a black panel in
    /// looked like a grey ghost sliding down the screen: at 40% opacity a black
    /// rectangle over white is simply grey, and it stayed that way for most of
    /// the opening. Against a dark wallpaper nobody would ever have seen it,
    /// which is why it survived this long.
    ///
    /// The panel is meant to read as the notch itself stretching open, and the
    /// notch is not translucent for a third of a second. Growing it at full
    /// black says that; fading it in says a window is appearing. Going out
    /// still fades, because retreating INTO the notch is helped by softening.
    static func drop(
        widthRatio: CGFloat,
        heightRatio: CGFloat,
        anchor: UnitPoint,
        arrivesOpaque: Bool = false
    ) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: DropEffect(
                    widthRatio: widthRatio,
                    heightRatio: heightRatio,
                    fade: arrivesOpaque ? 1 : 0,
                    anchor: anchor
                ),
                identity: DropEffect(widthRatio: 1, heightRatio: 1, fade: 1, anchor: anchor)
            ),
            removal: .modifier(
                active: DropEffect(
                    widthRatio: widthRatio * 0.92,
                    heightRatio: max(heightRatio * 0.6, 0.02),
                    fade: 0,
                    anchor: anchor
                ),
                identity: DropEffect(widthRatio: 1, heightRatio: 1, fade: 1, anchor: anchor)
            )
        )
    }
}
