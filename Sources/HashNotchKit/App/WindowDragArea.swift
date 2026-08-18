import AppKit
import SwiftUI

/// A patch of window you can drag the whole window by — the job a title bar
/// does on an ordinary window.
///
/// These panels are borderless, so there is no title bar to take hold of, and
/// they open in the middle of the screen over whatever is being worked on.
///
/// `isMovableByWindowBackground` alone does not achieve this, which is the part
/// worth writing down. AppKit only begins a background drag if the view the
/// click landed on says it may: it asks the hit-tested view for
/// `mouseDownCanMoveWindow`. The whole of a SwiftUI panel is ONE `NSHostingView`,
/// and it answers false — it wants those events for its own gestures and
/// buttons — so the flag is set, looks right in the source, and nothing moves.
///
/// Overriding that on the hosting view itself would be worse than useless: a
/// view that may move the window never receives the mouse-down at all, so every
/// button in the panel would stop responding.
///
/// So the drag region is a real `NSView` laid OVER the part of the panel that
/// has nothing to click — the icon and the title. AppKit drags natively from
/// there, which is smoother than following the pointer by hand and cannot
/// develop the feedback loop a SwiftUI `DragGesture` does when the thing it is
/// measuring against is the window it is moving. Controls stay clickable
/// because the region deliberately does not cover them.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        /// Invisible, and never the reason a click is swallowed anywhere else.
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) === self ? self : nil
        }
    }
}
