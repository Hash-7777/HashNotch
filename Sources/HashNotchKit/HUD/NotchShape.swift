import SwiftUI

/// The island's silhouette: square across the top, rounded along the bottom.
///
/// Square at the top because the island hangs from the top of the screen and
/// has to meet it without a seam — a rounded top edge would show daylight
/// between the shape and the bezel and give the whole illusion away. Rounded
/// below because that is the part that reads as an object.
///
/// ## Why this is not `UnevenRoundedRectangle`
///
/// SwiftUI grew exactly this shape in macOS 13, which is what the island used.
/// That put the app's most fundamental piece of drawing behind a version check,
/// and the shape is not complicated: it is four lines and two corners. Owning
/// it costs a dozen lines and buys back every macOS the rest of the app can
/// run on.
///
/// The corners are quarter circles rather than SwiftUI's `.continuous`
/// squircle. The difference at these radii is under a point, and a shape that
/// draws identically everywhere is worth more than one that is subtly rounder
/// on newer systems than older ones.
struct NotchShape: InsettableShape, Equatable {
    /// The bottom corner radius. Clamped on use, so no caller can produce a
    /// shape that folds through itself.
    var radius: CGFloat
    /// How far in from the edge to draw. `InsettableShape` conformance exists
    /// for `strokeBorder`, which draws a line INSIDE the shape rather than
    /// straddling its edge — the island's hairline has to sit within the black
    /// silhouette, or half of it hangs outside and softens the join with the
    /// bezel.
    var inset: CGFloat = 0

    /// Animating the radius means the panel's roundness can be a live setting
    /// rather than something that only applies on the next launch.
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        // The radius shrinks with the inset so the inner curve stays concentric
        // with the outer one; keeping it fixed makes an inset border bulge at
        // the corners.
        NotchShape(radius: max(0, radius - amount), inset: inset + amount)
    }

    func path(in outer: CGRect) -> Path {
        let rect = outer.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        // Never more than half of either side: past that the two corners meet
        // and the shape starts inverting.
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
