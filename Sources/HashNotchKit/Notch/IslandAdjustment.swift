import Foundation
import CoreGraphics

/// A hand-made correction to where the island sits and how big it is, applied
/// on top of what was measured.
///
/// Automatic measurement is right on every Mac tested, but "every Mac" is not a
/// list anyone can finish: displays get mirrored, scaled, rotated and driven
/// through adapters that report their geometry loosely. Rather than pretend the
/// measurement can never be wrong, this lets it be corrected by hand — and,
/// because a correction that is right for a laptop is wrong for the external
/// display beside it, corrections are remembered per display.
public struct IslandAdjustment: Codable, Equatable, Sendable {
    /// Sideways nudge in points. Positive moves the island right.
    public var horizontal: Double = 0
    /// Downward nudge in points. Positive moves the island further down the
    /// screen, away from the top edge.
    public var vertical: Double = 0
    /// Points added to the island's resting width.
    public var width: Double = 0
    /// Points added to the island's resting height.
    public var height: Double = 0

    public init() {}

    /// True when nothing has been changed, so the UI can say "automatic"
    /// instead of showing four zeroes as though they were a configuration.
    public var isAutomatic: Bool {
        horizontal == 0 && vertical == 0 && width == 0 && height == 0
    }

    /// The limits the sliders offer. Wide enough to fix a genuinely
    /// mis-measured display, tight enough that the island cannot be pushed
    /// somewhere it can never be found again.
    public static let horizontalRange: ClosedRange<Double> = -240...240
    public static let verticalRange: ClosedRange<Double> = -20...200
    public static let widthRange: ClosedRange<Double> = -80...200
    /// Height has the widest headroom of the four. A notch is a fixed piece of
    /// hardware and needs almost none, but a display without one is being given
    /// a shape rather than matched to one — and the old ceiling of +40 was not
    /// enough to make that shape look deliberate on a large screen.
    public static let heightRange: ClosedRange<Double> = -12...90

    /// This adjustment with every value forced inside its range. Applied on the
    /// way in, so a hand-edited preferences file cannot push the island off the
    /// screen entirely.
    public var clamped: IslandAdjustment {
        var copy = self
        copy.horizontal = min(max(horizontal, Self.horizontalRange.lowerBound), Self.horizontalRange.upperBound)
        copy.vertical = min(max(vertical, Self.verticalRange.lowerBound), Self.verticalRange.upperBound)
        copy.width = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        copy.height = min(max(height, Self.heightRange.lowerBound), Self.heightRange.upperBound)
        return copy
    }

    /// The measured geometry with this correction applied.
    ///
    /// The rect keeps its centre while growing, so widening the island opens it
    /// evenly on both sides instead of dragging it sideways.
    public func applied(to geometry: NotchGeometry) -> NotchGeometry {
        let safe = clamped
        guard !safe.isAutomatic else { return geometry }

        let rect = geometry.notchRect
        let newWidth = max(24, rect.width + safe.width)
        let newHeight = max(8, rect.height + safe.height)
        let adjusted = CGRect(
            x: rect.midX + safe.horizontal - newWidth / 2,
            y: rect.maxY - safe.vertical - newHeight,
            width: newWidth,
            height: newHeight
        )

        return NotchGeometry(
            screenFrame: geometry.screenFrame,
            notchRect: adjusted,
            hasNotch: geometry.hasNotch,
            islandTop: geometry.islandTop - safe.vertical
        )
    }
}
