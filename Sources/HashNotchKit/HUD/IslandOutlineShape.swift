import SwiftUI

/// The island's edge, minus the edge that is not there.
///
/// `NotchShape` is square across the top on purpose: the island hangs from the
/// top of the screen and has to meet it without a seam. That is right for the
/// black silhouette and wrong for a line drawn along it — stroking the closed
/// shape ran the colour straight across the top and turned it through two hard
/// right angles, which is the one part of the island that is not an edge at
/// all. On the hardware it sits under the bezel; on a screen without a notch it
/// sits under the menu bar. Either way there is nothing up there to outline,
/// and a corner drawn where the eye expects the shape to continue reads as
/// sharp and unfinished.
///
/// So this traces the three sides that ARE edges — down the right, around the
/// bottom, up the left — and stops. An open path, deliberately: the two ends
/// are then faded out where they approach the top, so the colour appears to run
/// off under the bezel rather than stopping dead against it.
///
/// The geometry is `NotchShape`'s, minus its top line and its closing segment,
/// so the line sits exactly on the silhouette it belongs to and cannot drift
/// from it if that shape is ever adjusted.
package struct IslandOutlineShape: Shape {
    package var radius: CGFloat

    package init(radius: CGFloat) { self.radius = radius }

    package var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    package func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
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
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}
