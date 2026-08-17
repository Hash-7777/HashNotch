import AppKit

/// A borderless, transparent overlay window that floats above the menu bar so
/// the HUD can draw in and around the notch. It sits on every Space and does not
/// steal focus. It is fully click-through (`ignoresMouseEvents = true`) so it can
/// never block the menu bar or anything else — hover is detected separately via
/// a global mouse-position monitor that only observes, never captures.
public final class NotchWindow: NSWindow {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
