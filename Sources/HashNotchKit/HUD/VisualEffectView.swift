import SwiftUI
import AppKit

/// The app's glass: every frosted surface — the panel's "Frosted glass" fill,
/// the settings window, the opening window, the quit confirmation — is drawn by
/// this one view, so they all change together.
///
/// On macOS 26 and later it is Liquid Glass, through AppKit's own
/// `NSGlassEffectView`, which is what the system's own surfaces are made of. It
/// blurs and refracts what is behind the window, catches the light along its
/// edge, and follows the system's own settings for it: macOS 27's transparency
/// slider, from clear to tinted, and Reduce Transparency. Drawing it any other
/// way would be an imitation that stops matching the system the first time
/// somebody moves that slider.
///
/// Before macOS 26 there is no Liquid Glass, and it is the frosted
/// `NSVisualEffectView` the app has always used, blending behind the window.
///
/// Every caller lays its own dark wash over this, so white text stays readable
/// over a white document behind the window. That is deliberate and is kept on
/// both paths: glass takes its brightness from what is behind it, and the only
/// guarantee of legibility over ANY background is darkening it enough that what
/// shows through is texture rather than brightness.
public struct VisualEffectView: NSViewRepresentable {
    /// The frosted material used before macOS 26. Liquid Glass has no
    /// materials; it is one surface that adapts to what is behind it.
    public let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material = .hudWindow) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = SteadyGlassEffectView()
            glass.style = .regular
            // The app is dark throughout, so the glass is asked for its dark
            // form rather than following a light system appearance into a pale
            // surface under white text.
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        let view = SteadyVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {
        (view as? NSVisualEffectView)?.material = material
    }
}

/// The frosted layer, with one thing taken away from it: it never offers itself
/// as somewhere the window can be dragged from.
///
/// A stock `NSVisualEffectView` answers `mouseDownCanMoveWindow` with true
/// (measured, macOS 26). On a borderless panel that is movable by its
/// background, and whose whole surface is one of these, that makes every empty
/// point on the window a place to pick it up — including the empty part of a
/// row you were trying to drag somewhere else. The window moved instead, and
/// the drag never reached the list.
///
/// Dragging the window is not lost, it is placed: `WindowDragArea` is the one
/// view that still says yes, and it covers the header.
package final class SteadyVisualEffectView: NSVisualEffectView {
    package override var mouseDownCanMoveWindow: Bool { false }
}

/// The Liquid Glass layer, held to the same rule as the frosted one: it is a
/// surface, never a place the window can be dragged from.
@available(macOS 26.0, *)
package final class SteadyGlassEffectView: NSGlassEffectView {
    package override var mouseDownCanMoveWindow: Bool { false }
}
