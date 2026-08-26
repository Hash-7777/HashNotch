import SwiftUI
import AppKit

/// A frosted-glass background (like macOS Control Center), backed by
/// `NSVisualEffectView` with behind-window blending so it blurs the wallpaper
/// and windows behind it.
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material = .hudWindow) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = SteadyVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
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
