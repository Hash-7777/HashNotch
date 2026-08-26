import AppKit
import SwiftUI

/// A patch of window you can drag the whole window by — the job a title bar
/// does on an ordinary window.
///
/// These panels are borderless, so there is no title bar to take hold of, and
/// they open in the middle of the screen over whatever is being worked on.
///
/// `isMovableByWindowBackground` is the switch that allows a drag at all; the
/// view the click lands on decides whether one starts, through
/// `mouseDownCanMoveWindow`. Both have to agree, and the second one is where
/// the surprise is: nearly everything says yes by default. Measured on
/// macOS 26 — a plain `NSView`, an `NSVisualEffectView` and an `NSHostingView`
/// all answer true. A SwiftUI panel is one hosting view over a frosted one, so
/// with the switch on, the whole surface was a drag handle and this view was
/// decorative.
///
/// That is not a cosmetic mistake. A window that moves when you press anywhere
/// eats the press, so a drag meant for something inside — reordering the
/// indicators, in particular — never arrived.
///
/// So the two big surfaces now decline (`SteadyVisualEffectView`,
/// `PanelHostingView`) and this is the one view that accepts, laid OVER the
/// part of the panel that has nothing to click. AppKit drags natively from
/// here, which is smoother than following the pointer by hand and cannot
/// develop the feedback loop a SwiftUI `DragGesture` does when the thing it is
/// measuring against is the window it is moving.
///
/// Overriding the hosting view the other way — to true — would be worse than
/// useless: a view that may move the window never receives the mouse-down at
/// all, so every button in the panel would stop responding.
package struct WindowDragArea: NSViewRepresentable {
    package init() {}

    package func makeNSView(context: Context) -> NSView { DragView() }
    package func updateNSView(_ nsView: NSView, context: Context) {}

    package final class DragView: NSView {
        package override var mouseDownCanMoveWindow: Bool { true }
        /// Invisible, and never the reason a click is swallowed anywhere else.
        package override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) === self ? self : nil
        }
    }
}

/// The hosting view a borderless panel is built on, with the same thing taken
/// away from it: it never offers itself as somewhere the window can be dragged
/// from.
///
/// Used instead of `NSHostingController` so the override has somewhere to live.
/// The window resizes its own content view, so nothing is lost by holding the
/// hosting view directly.
package final class PanelHostingView<Content: View>: NSHostingView<Content> {
    package override var mouseDownCanMoveWindow: Bool { false }

    package required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
