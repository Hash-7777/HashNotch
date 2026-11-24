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
/// The corners are continuous curves, the kind the system draws its own
/// rounded shapes with, rather than quarter circles: the curve eases out of the
/// straight side instead of turning abruptly where an arc meets a line, which
/// is what made the strip's ends look stepped. They are drawn here, by
/// `IslandCorner`, rather than taken from SwiftUI's `.continuous` style, so
/// the shape stays the same on every macOS the app runs on.
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
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        IslandCorner.bottomRight(of: rect, radius: radius, in: &path)
        IslandCorner.bottomLeft(of: rect, radius: radius, in: &path)
        path.closeSubpath()
        return path
    }
}

/// The island's bottom corners, as continuous curves.
///
/// A quarter circle joins a straight side with a sudden change of curvature,
/// and at the strip's small size the eye reads that join as a step. This
/// corner starts curving further from the corner and eases in, one cubic per
/// corner, sized so it passes through the same point at 45 degrees as the
/// circle of the same radius would. Its curvature still begins gently rather
/// than all at once, which is what reads as smooth.
package enum IslandCorner {
    /// How far along each side the curve begins, as a multiple of the radius:
    /// the figure the system's own continuous corners use.
    package static let reach: CGFloat = 1.528
    /// Where the control points sit, as a fraction of `reach` from the corner.
    /// Chosen so the curve's midpoint matches the circle's.
    package static let pull: CGFloat = 0.178

    /// How far along each side a corner of `radius` reaches in `rect`: never
    /// past half the width, so two corners never cross, nor past the height.
    package static func extent(radius: CGFloat, in rect: CGRect) -> CGFloat {
        max(0, min(radius * reach, rect.width / 2, rect.height))
    }

    /// From the right side, around the bottom-right corner, onto the bottom.
    package static func bottomRight(of rect: CGRect, radius: CGFloat, in path: inout Path) {
        let l = extent(radius: radius, in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addCurve(
            to: CGPoint(x: rect.maxX - l, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - l * pull),
            control2: CGPoint(x: rect.maxX - l * pull, y: rect.maxY))
    }

    /// Along the bottom, around the bottom-left corner, onto the left side.
    package static func bottomLeft(of rect: CGRect, radius: CGFloat, in path: inout Path) {
        let l = extent(radius: radius, in: rect)
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - l),
            control1: CGPoint(x: rect.minX + l * pull, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - l * pull))
    }
}
