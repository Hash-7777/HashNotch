import AppKit

/// Measures where the island should sit on a given screen, using public AppKit
/// APIs only.
///
/// On a notched Mac, `safeAreaInsets.top` is the notch height and the
/// `auxiliaryTop*Area` rects are the usable menu-bar strips either side of it —
/// the gap between them is the notch itself, and the island wears it exactly.
///
/// On a screen **without** a notch there is nothing to blend into, and the top
/// of the screen is the menu bar. Painting a black shape up there would cover
/// it, which reads as a fault rather than a feature. So the island hangs below
/// the menu bar instead, as a small pill of its own: deliberate, not broken.
public struct NotchGeometry {
    public let screenFrame: CGRect
    public let notchRect: CGRect
    public let hasNotch: Bool
    /// The y coordinate the island hangs from: the screen's top edge when there
    /// is a notch to match, the bottom of the menu bar when there is not.
    public let islandTop: CGFloat

    public init(
        screenFrame: CGRect,
        notchRect: CGRect,
        hasNotch: Bool,
        islandTop: CGFloat? = nil
    ) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
        self.islandTop = islandTop ?? screenFrame.maxY
    }

    /// The stand-in island's size on a screen with no notch. Narrow enough to
    /// read as a deliberate pill rather than a bar across the top.
    public static let notchlessWidth: CGFloat = 132
    public static let notchlessHeight: CGFloat = 26

    public static func current(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchRect = CGRect(
                x: left.maxX,
                y: frame.maxY - topInset,
                width: max(0, right.minX - left.maxX),
                height: topInset
            )
            return NotchGeometry(
                screenFrame: frame,
                notchRect: notchRect,
                hasNotch: true,
                islandTop: frame.maxY
            )
        }

        // No notch. The island still hangs from the very top of the screen, so
        // it meets the bezel exactly the way the hardware notch does.
        //
        // It used to hang from the BOTTOM of the menu bar instead, on the
        // reasoning that painting over the menu bar would be taking space that
        // is not ours. The result floated: a dark pill with a strip of desktop
        // above it, attached to nothing, which reads as a mistake rather than
        // as restraint — and no amount of adjusting could close that gap,
        // because growing the island only ever grew it downwards, away from the
        // edge it needed to reach.
        //
        // So it is anchored to the top and made exactly as tall as the menu bar,
        // which fills that band precisely and reads as a notch that was always
        // there. The space it takes is the middle of the menu bar, which is the
        // one part of it macOS never uses: app menus sit hard left, status items
        // hard right. The PANEL still opens below the menu bar, so nothing that
        // drops down ever covers a menu.
        return notchless(screenFrame: frame, menuBarHeight: menuBarHeight(for: screen))
    }

    /// The stand-in island for a display with no notch.
    ///
    /// Split out from `forScreen` and made pure so the rule can be checked
    /// without an NSScreen — the previous checks built a geometry by hand and
    /// asserted things about it, which tested the fixture rather than the rule
    /// and would have passed no matter what this did.
    package static func notchless(screenFrame frame: CGRect, menuBarHeight bar: CGFloat) -> NotchGeometry {
        let height = min(max(bar, notchlessMinHeight), notchlessMaxHeight)
        let notchRect = CGRect(
            x: frame.midX - notchlessWidth / 2,
            y: frame.maxY - height,
            width: notchlessWidth,
            height: height
        )
        return NotchGeometry(
            screenFrame: frame,
            notchRect: notchRect,
            hasNotch: false,
            islandTop: frame.maxY
        )
    }

    /// Bounds on the height of a drawn island, for a display that has no notch
    /// to copy. The menu bar decides it within these — the point is to fill that
    /// band exactly — but a screen reporting something absurd should not produce
    /// a black slab or an invisible sliver.
    package static let notchlessMinHeight: CGFloat = 22
    package static let notchlessMaxHeight: CGFloat = 38

    /// How tall the menu bar is on this screen. The status bar's own thickness
    /// is the reliable answer; the others are floors for the case where the
    /// system reports something implausible.
    package static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let reported = NSStatusBar.system.thickness
        let unusable = screen.frame.maxY - screen.visibleFrame.maxY
        return max(reported, min(unusable, 40), 24)
    }

    /// The screen most likely to have a notch, else the main screen.
    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// A stable key for remembering per-display adjustments. Falls back to the
    /// frame size when the display id is unavailable, which still tells two
    /// differently sized screens apart.
    public static func displayKey(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        let frame = screen.frame
        return "frame-\(Int(frame.width))x\(Int(frame.height))"
    }
}
