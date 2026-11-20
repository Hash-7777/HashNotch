import AppKit
import SwiftUI

/// The window the menu bar item opens: a pane of glass hanging under the item,
/// the way the system's own menu bar items open theirs.
///
/// It is a NON-ACTIVATING panel, and that is the whole point of it. It used to
/// be an `NSPopover` opened after making this app the active one, because a
/// popover in an inactive app ignores the first click. Activating took focus
/// away from whatever window somebody was working in — their document stopped
/// being the key window, the menu bar's app menus changed — for a glance at
/// three numbers. And a popover that closes itself on any outside click closed
/// on the very click meant to close it, then reopened, so it could not be
/// toggled quickly. Neither is how a menu bar item behaves.
///
/// So it never takes the keyboard either. A panel that became the key window,
/// even a non-activating one, still took keyboard focus from the window
/// somebody was typing in — measured: this app went from inactive to active the
/// moment it did. One that never becomes key leaves this app inactive and the
/// other app's window exactly as it was, which is what the system's own items
/// do. The price is Escape, which needs the keyboard; a press of the item or a
/// click anywhere else closes it, as they close the system's. Its controls take
/// the first click, so nothing is lost by its not being key.
@MainActor
package final class MenuBarPanel {
    private let window: MenuBarPanelWindow
    private let host: FirstClickHostingView<AnyView>
    private var outsideClickMonitor: Any?
    /// The item it hangs from, so a click on the item is told apart from a
    /// click anywhere else.
    private weak var anchorButton: NSStatusBarButton?
    /// Bumped on every open and close, so a fade-out that finishes after the
    /// panel was opened again does not take it off the screen.
    private var generation = 0
    private(set) var isShown = false

    /// Room between the menu bar and the top of the panel.
    static let gap: CGFloat = 5
    /// How long it takes to appear and to go: quick enough to read as
    /// immediate, long enough not to blink.
    static let fade: TimeInterval = 0.12

    init<Content: View>(content: Content) {
        let root = AnyView(
            content
                .background(
                    ZStack {
                        VisualEffectView(material: .menu)
                        Color.black.opacity(0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .environment(\.colorScheme, .dark)
                // Drawn as active controls, as they would be in a window that
                // had the keyboard: this one never does, by design.
                .environment(\.controlActiveState, .key)
        )
        host = FirstClickHostingView(rootView: root)
        window = MenuBarPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.contentView = host
    }

    /// Open under `button`, or close if it is open.
    func toggle(below button: NSStatusBarButton) {
        isShown ? hide() : show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        guard let anchor = button.window?.frame else { return }
        anchorButton = button
        generation &+= 1
        isShown = true
        place(under: anchor, on: button.window?.screen)
        if !window.isVisible { window.alphaValue = 0 }
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            window.animator().alphaValue = 1
        }
        watchForOutsideClicks()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        generation &+= 1
        let token = generation
        stopWatching()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.window.orderOut(nil)
            }
        })
    }

    /// Resize to what it shows, keeping its top edge where it is — for when a
    /// figure switched on or off changes the content's height while it is open.
    func refit() {
        guard isShown else { return }
        let size = host.fittingSize
        var frame = window.frame
        guard size.width > 0, size.height > 0, frame.size != size else { return }
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        window.setFrame(frame, display: true)
    }

    /// Hanging from just below the menu bar, its left edge on the item's, and
    /// kept on the screen.
    private func place(under anchor: NSRect, on screen: NSScreen?) {
        let size = host.fittingSize
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let top = min(anchor.minY, visible.maxY) - Self.gap
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - 8 - size.width)
        window.setFrame(NSRect(x: x.rounded(), y: (top - size.height).rounded(),
                               width: size.width, height: size.height), display: true)
    }

    /// A click anywhere else puts it away.
    ///
    /// Except a click on the item itself, which is the item's to answer: it
    /// toggles. A global monitor does not see this app's own clicks on the
    /// panel, but on this system it DOES see the click on the item — the menu
    /// bar's items are drawn by the system, not in this app's windows — so
    /// without this a second press closed the panel here and reopened it in
    /// the item's own action, and the panel never closed.
    private func watchForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let item = self.anchorButton?.window?.frame ?? .zero
                guard !Self.isOnItem(NSEvent.mouseLocation, item: item) else { return }
                self.hide()
            }
        }
    }

    /// Whether a click at `point`, in screen coordinates, landed on the item.
    /// A point of slack on each side, since the item's edge is drawn by the
    /// system and a click on its border belongs to it.
    package static func isOnItem(_ point: NSPoint, item: NSRect) -> Bool {
        !item.isEmpty && item.insetBy(dx: -1, dy: -1).contains(point)
    }

    private func stopWatching() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}

/// A panel that never takes the keyboard or becomes the app's main window, so
/// opening it changes nothing about the window somebody is working in.
package final class MenuBarPanelWindow: NSPanel {
    package override var canBecomeKey: Bool { false }
    package override var canBecomeMain: Bool { false }
}

/// A hosting view whose controls answer the first click, rather than spending
/// it on bringing the panel forward — the panel is already in front.
package final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    package override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    package override var mouseDownCanMoveWindow: Bool { false }
}
