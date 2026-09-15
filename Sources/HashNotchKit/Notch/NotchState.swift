import SwiftUI

/// Observable UI state and sizing for the black notch island.
///
/// The island has two sizes: collapsed (matching the physical notch, so it looks
/// like the notch) and expanded (a rounded black panel that drops down below the
/// menu bar). Because the expanded content lives *below* the menu bar, it never
/// overlaps app menus or status items.
@MainActor
public final class NotchState: ObservableObject {
    /// Whether the island is expanded (dropped down) or collapsed.
    @Published public var isExpanded: Bool = false

    /// Published rather than fixed, so dragging a size slider in Settings
    /// reshapes the island under your hand instead of after you let go.
    @Published public private(set) var notchWidth: CGFloat = 0
    @Published public private(set) var notchHeight: CGFloat = 0

    @Published public private(set) var collapsedWidth: CGFloat = 0
    @Published public private(set) var collapsedHeight: CGFloat = 0
    @Published public private(set) var liveLeadingWidth: CGFloat = NotchState.leadingWidth(forHeight: NotchState.minimumContentHeight)
    /// The black between a strip picture and the strip's edges — above, below,
    /// and at the rounded end alike, so the picture sits centred in that end.
    @Published public private(set) var liveInset: CGFloat = NotchState.inset(forHeight: NotchState.minimumContentHeight)
    /// The strip's corner radius, concentric with the picture's: see
    /// `cornerRadius(forHeight:)`.
    @Published public private(set) var liveCornerRadius: CGFloat = NotchState.cornerRadius(forHeight: NotchState.minimumContentHeight)
    @Published public private(set) var liveTrailingWidth: CGFloat = 170
    @Published public private(set) var liveWidth: CGFloat = 0
    @Published public private(set) var liveHeight: CGFloat = 0
    @Published public private(set) var expandedWidth: CGFloat = 0
    @Published public private(set) var expandedHeight: CGFloat = 460
    /// How tall the open panel may be on this display: the room below the
    /// island, less a margin at the bottom. The panel's rows scroll inside it
    /// when they would not fit, rather than running off the screen.
    @Published public private(set) var panelRoom: CGFloat = .greatestFiniteMagnitude

    public init(geometry: NotchGeometry) {
        apply(geometry: geometry)
    }

    /// Resize to a new measurement. Called at launch, when the display changes,
    /// and on every tick of a size slider.
    public func apply(geometry: NotchGeometry) {
        let width = geometry.notchRect.width
        let measured = geometry.notchRect.height
        notchWidth = width

        // Collapsed: EXACTLY what was measured, so the idle black shape is
        // invisible against the hardware — no lip poking out below it.
        //
        // Taken as it stands, with no floor under it. There is nothing drawn in
        // this shape to fit, so there is nothing for a floor to protect, and a
        // floor here is the one thing that can break the promise this line is
        // making. See `minimumContentHeight`.
        collapsedWidth = width
        collapsedHeight = measured

        // Everything below holds something, so it gets the floor.
        let height = max(measured, Self.minimumContentHeight)
        notchHeight = height

        // Expanded: width sized to the content; height is generous only for the
        // hover zone (the panel itself sizes to its content).
        expandedWidth = max(width + 120, 300)
        expandedHeight = 460
        panelRoom = Self.panelRoom(islandTop: geometry.islandTop, screenFrame: geometry.roomFrame)

        // Compact-live: content hugs the notch — a small art tile on the left,
        // a title on the right — like the iPhone's compact Dynamic Island.
        // Leading is a fixed clearance beside the notch; trailing is the MAX
        // the visible pill can reach (18pt gap + the 140pt title cap + 12pt
        // breathing room) — the pill hugs the actual content within it, and
        // this max only sizes the positioning box, the hover zone, and the
        // window so a fully-scrolling long title is always covered.
        liveLeadingWidth = Self.leadingWidth(forHeight: height)
        liveInset = Self.inset(forHeight: height)
        liveCornerRadius = Self.cornerRadius(forHeight: height)
        liveTrailingWidth = 170
        liveWidth = width + liveLeadingWidth + liveTrailingWidth
        liveHeight = height + Self.liveLip
    }

    /// The least height the live strip can be drawn at and still hold what goes
    /// in it. The artwork beside a track is 20 points; this leaves four points
    /// of black above and below it, so the picture sits inside the strip
    /// rather than against its edge.
    ///
    /// It used to be applied to the idle shape too, and on a notched Mac that
    /// was invisible: every notch this app has measured is at least 28 points
    /// tall, so the floor never once came into play. A display with NO notch is
    /// a different size entirely. Its island is deliberately made exactly as
    /// tall as the menu bar — 24 or 25 points on the machines measured — so
    /// there the floor came into play every time, and made the idle shape three
    /// or four points taller than the band it exists to fill.
    ///
    /// That is precisely the thing `liveLip` describes and rejects: a black lip
    /// hanging below the bar onto the wallpaper, visible against anything that
    /// is not black. On a notchless Mac it was on screen the entire time the
    /// app was running, and it could not be reproduced on the hardware the app
    /// was built on.
    ///
    /// So the floor applies only where there is content to fit. The trade is
    /// that on a display whose menu bar is shorter than this, the strip is a
    /// few points taller than the idle shape and dips just below the bar while
    /// something is live. That is a pill with a picture and a title in it,
    /// which reads as a thing that is happening; the idle silhouette had
    /// nothing to justify it.
    public static let minimumContentHeight: CGFloat = 28

    /// The one small picture the strip carries left of the notch — an album
    /// cover, an app's icon, an activity's mark — and its corners. Every
    /// feature draws its strip picture at this size, so the strip can be built
    /// around it exactly.
    public static let livePictureSize: CGFloat = 20
    public static let livePictureRadius: CGFloat = 6
    /// How far the picture sits from the hardware: the iPhone's hug.
    public static let liveNotchGap: CGFloat = 6

    /// The black around the picture, equal on every side that has one.
    ///
    /// The picture is centred in the strip's height, so above and below it
    /// there is `(height − picture) / 2`. The same margin at the rounded end
    /// puts it in the middle of that end rather than tucked toward the notch
    /// with a slab of black beyond it.
    public static func inset(forHeight height: CGFloat) -> CGFloat {
        max(0, (height - livePictureSize) / 2)
    }

    /// The strip's corner radius: the picture's own radius plus the margin
    /// around it.
    ///
    /// That is what makes the two curves concentric — one centre, the strip's
    /// corner simply the picture's corner grown by the margin — which is the
    /// thing that reads as made rather than placed. The strip was a fixed 14
    /// around a 5-point corner at a lopsided margin, and the two curves visibly
    /// disagreed at the one place they sit side by side. On a 28-point strip
    /// this is 10, the hardware notch's own corner; on a taller notch it grows
    /// with the margin so the picture stays centred and concentric.
    public static func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        inset(forHeight: height) + livePictureRadius
    }

    /// The strip's side left of the notch: the gap to the hardware, the
    /// picture, and the margin at the rounded end. Nothing else — it was a flat
    /// 56 that reached well past what it held.
    public static func leadingWidth(forHeight height: CGFloat) -> CGFloat {
        liveNotchGap + livePictureSize + inset(forHeight: height)
    }

    /// The room below the island for the open panel.
    ///
    /// ONE calculation, used by the window, the keep-open zone and the panel's
    /// own rows. The window used to be capped here while the panel inside it
    /// was not, so a panel with enough indicators switched on laid itself out
    /// taller than the screen and the window simply cut it off: the last rows
    /// were unreachable, with nothing to scroll.
    package static func panelRoom(islandTop: CGFloat, screenFrame: CGRect) -> CGFloat {
        max(0, islandTop - screenFrame.minY - NotchWindowController.panelBottomMargin)
    }

    /// How much room is left below the notch for the coloured line — and it is
    /// room for the LINE, not black.
    ///
    /// The strip used to be exactly the notch's height, which was right until
    /// the island started wearing a colour. The notch's underside is then also
    /// the pill's bottom edge, and a line centred on that edge is half behind
    /// the hardware: it survives on the two shoulders and thins to nothing
    /// across the middle, which reads as a line broken in half.
    ///
    /// The first answer was to make the black itself three points taller, so
    /// the line had black to sit on. That worked and it was the wrong trade: a
    /// pill that ends lower than the hardware is a black lip hanging over the
    /// wallpaper, visible against anything that is not black, and the notch
    /// stops looking like the notch.
    ///
    /// So the BLACK is exactly the notch again, and this is the clearance the
    /// window keeps underneath it — transparent, drawn into by nothing except
    /// the line and its glow. The line is drawn just OUTSIDE the pill's bottom
    /// edge rather than centred on it, which puts all of it on screen, in the
    /// couple of points directly below the hardware where there is display to
    /// light up. Two points is the line, its glow, and the blur that softens
    /// it; anything more would be room nothing draws in.
    public static let liveLip: CGFloat = 2

    /// The usable width on each side of the physical notch inside the open
    /// panel, where the app's own controls live.
    ///
    /// The panel is wider than the notch, so the band across its top — as tall
    /// as the notch itself — has a strip of panel showing either side of the
    /// hardware. That band exists either way: it is the clearance that keeps the
    /// first row from being swallowed by the notch. Putting the quit and
    /// settings buttons in it costs no height at all and means they are placed
    /// by the layout rather than floated over whichever row happens to be first.
    public var shoulderWidth: CGFloat {
        max(0, (expandedWidth - notchWidth) / 2)
    }

    /// The narrowest a shoulder may be and still hold a control with room to
    /// breathe — a 24pt button plus its inset from the panel's edge.
    ///
    /// `expandedWidth` is `max(notchWidth + 120, 300)`, so a shoulder is never
    /// below 60 points on any hardware the app measures; this is the floor the
    /// checks hold that guarantee against, so a future change to the panel's
    /// width cannot quietly squeeze the buttons out.
    public static let minimumShoulderWidth: CGFloat = 40

    /// How big the island's own controls are drawn.
    ///
    /// Held here rather than in the view because the geometry depends on it:
    /// each control is centred in its shoulder, so half of this is what decides
    /// whether it clears the hardware and the panel's edge.
    public static let controlSize: CGFloat = 26

    /// The gap between a centred control and the physical notch beside it.
    ///
    /// Negative would mean the control is drawn under the hardware, where it
    /// cannot be seen or clicked — worth failing a check over rather than
    /// finding out on a Mac with a wider notch than the one this was built on.
    public var controlClearance: CGFloat {
        shoulderWidth / 2 - Self.controlSize / 2
    }

    /// How far RIGHT the live strip must shift so its internal notch gap sits
    /// exactly on the physical notch. The sides are deliberately unequal
    /// (small art left, wide title right); centering the whole strip would
    /// land the gap (trailing − leading) / 2 points LEFT of the physical
    /// notch — which put the artwork far from the notch and buried the
    /// title's start underneath it (confirmed by photographing the physical
    /// screen; screenshots can't show this, they include the hidden pixels
    /// behind the notch).
    public var liveCenterOffset: CGFloat {
        (liveTrailingWidth - liveLeadingWidth) / 2
    }

    /// Where the notch sits inside the live strip, as a fraction of its width.
    ///
    /// The strip is deliberately lopsided — a small artwork tile to the left of
    /// the notch, a much wider title to its right — so its centre is not the
    /// notch. Anything that should converge on the hardware (a transition
    /// anchor, for one) needs this rather than 0.5, or it collapses toward a
    /// point beside the notch instead of into it.
    public var notchAnchorInLiveStrip: CGFloat {
        guard liveWidth > 0 else { return 0.5 }
        return (liveLeadingWidth + notchWidth / 2) / liveWidth
    }

    public func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        // The change MUST run inside an animation transaction — the island's
        // content transitions (the emerging-from-the-notch drop) only animate
        // with a transaction; without one, only the pill resizes and the
        // content pops in. Direction-aware: soft settle open, damped close.
        withAnimation(
            expanded
                ? .spring(response: 0.55, dampingFraction: 0.72)
                : .spring(response: 0.42, dampingFraction: 0.98)
        ) {
            isExpanded = expanded
        }
    }
}
