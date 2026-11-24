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
    /// Whether the content is open, which the surface animates from: it grows
    /// down out of the menu bar on a spring, and folds back up to go.
    private let presence = MenuBarPanelPresence()

    /// Room between the menu bar and the top of the panel.
    package static let gap: CGFloat = 5
    /// How long closing takes before the window leaves the screen: the length
    /// of the surface's own closing animation.
    static let closing: TimeInterval = 0.16
    /// Transparent room around the panel inside its window, for the shadow the
    /// panel draws itself. Drawn rather than the window's own, because the
    /// window's shadow is worked out once from what the window shows and
    /// cannot follow a panel growing into place; this one moves with it. Next
    /// to nothing at the top, where the panel hangs just under the menu bar.
    package static let shadowRoom = NSEdgeInsets(top: 4, left: 28, bottom: 40, right: 28)

    init<Content: View>(content: Content) {
        let room = Self.shadowRoom
        let root = AnyView(
            MenuBarPanelSurface(content: content, presence: presence)
                .padding(EdgeInsets(top: room.top, leading: room.left,
                                    bottom: room.bottom, trailing: room.right))
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
        window.hasShadow = false
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
        let click = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(click) } ?? button.window?.screen
        place(under: Self.anchor(item: anchor, click: click, screen: screen?.frame), on: screen)
        let wasVisible = window.isVisible
        if !wasVisible {
            // Laid out closed first, so the spring has somewhere to start from.
            presence.isOpen = false
            host.layoutSubtreeIfNeeded()
        }
        window.alphaValue = 1
        window.orderFrontRegardless()
        // A turn later, once the closed state has been drawn: the opening is
        // an animation from it, not a jump to the end.
        DispatchQueue.main.async { [presence] in
            MainActor.assumeIsolated {
                withAnimation(MenuBarPanelPresence.opening) { presence.isOpen = true }
            }
        }
        watchForOutsideClicks()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        generation &+= 1
        let token = generation
        stopWatching()
        withAnimation(MenuBarPanelPresence.closingAnimation) { presence.isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closing) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.window.orderOut(nil)
            }
        }
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

    /// Where to hang it from: the item, or — when the click came from a menu
    /// bar on another display, which shows the same item while the item's own
    /// window stays where it is — the point clicked, on the display clicked.
    package static func anchor(item: NSRect, click: NSPoint, screen: NSRect?) -> NSRect {
        guard let screen, !item.isEmpty, !screen.intersects(item) else { return item }
        return NSRect(x: click.x - item.width / 2, y: screen.maxY - item.height,
                      width: item.width, height: item.height)
    }

    /// Hanging from just below the menu bar, its left edge on the item's, and
    /// kept on the screen.
    private func place(under anchor: NSRect, on screen: NSScreen?) {
        let fitting = host.fittingSize
        let room = Self.shadowRoom
        let size = NSSize(width: fitting.width - room.left - room.right,
                          height: fitting.height - room.top - room.bottom)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let top = min(anchor.minY, visible.maxY) - Self.gap
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - 8 - size.width)
        let panel = NSRect(x: x.rounded(), y: (top - size.height).rounded(),
                           width: size.width, height: size.height)
        window.setFrame(Self.windowFrame(panel: panel), display: true)
    }

    /// The window around a panel at `panel`: the panel, and the room its
    /// shadow is drawn in. Placement is worked out for the panel, so the panel
    /// lands exactly where it did when the window held nothing else.
    package static func windowFrame(panel: NSRect) -> NSRect {
        let room = shadowRoom
        return NSRect(x: panel.minX - room.left, y: panel.minY - room.bottom,
                      width: panel.width + room.left + room.right,
                      height: panel.height + room.top + room.bottom)
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

/// Whether the panel's content is open. The window is on screen a moment
/// longer than this is true, so the closing animation has somewhere to play.
@MainActor
package final class MenuBarPanelPresence: ObservableObject {
    @Published package var isOpen = false
    package init() {}

    /// Out of the menu bar on a spring with a touch of give, so it lands
    /// rather than stops.
    static var opening: Animation {
        .spring(response: 0.34 * SystemGeneration.current.motionScale, dampingFraction: 0.8)
    }
    /// Back up quickly and without bounce: a closing panel is getting out of
    /// the way, and should not draw the eye.
    static var closingAnimation: Animation {
        .easeIn(duration: MenuBarPanel.closing)
    }
}

/// Lets the panel's contents arrive in turn as it opens.
private struct MenuBarPanelOpenKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the menu bar panel is closed or closing.
    var menuBarPanelOpen: Bool {
        get { self[MenuBarPanelOpenKey.self] }
        set { self[MenuBarPanelOpenKey.self] = newValue }
    }
}

/// The panel's glass, lit and lifted.
///
/// The app's own surface, with a lighter wash than the notch panel's so more of
/// what is behind shows through. Three things give it depth, each restrained:
/// an edge that is brighter along the top than the bottom, the way light
/// catches the rim of a pane of glass; a tight shadow where it meets what is
/// behind it; and a wide soft one beneath, so it reads as floating above the
/// window under it. No glow and no colour: depth comes from light and shade.
///
/// The wash is kept, lighter: glass takes its brightness from what is behind
/// it, and white text over a white document needs some darkening to stay
/// readable.
///
/// Opening, it grows down out of the menu bar from its top edge on a spring;
/// closing, it folds back up and fades. With Reduce Motion on it only fades.
package struct MenuBarPanelSurface<Content: View>: View {
    package static var cornerRadius: CGFloat { 16 }
    let content: Content
    @ObservedObject var presence: MenuBarPanelPresence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(content: Content, presence: MenuBarPanelPresence) {
        self.content = content
        self.presence = presence
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let open = presence.isOpen
        let still = open || reduceMotion
        content
            .environment(\.menuBarPanelOpen, open)
            .background(
                ZStack {
                    VisualEffectView(material: .menu)
                    Color.black.opacity(0.18)
                }
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.26), Color.white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .background(OuterShadow(shape: shape, color: .black.opacity(0.35), radius: 22, y: 14))
            .background(OuterShadow(shape: shape, color: .black.opacity(0.25), radius: 1.5, y: 1))
            .environment(\.colorScheme, .dark)
            .scaleEffect(still ? 1 : 0.94, anchor: .top)
            .offset(y: still ? 0 : -8)
            .opacity(open ? 1 : 0)
    }
}

/// A shadow cast only OUTSIDE a shape.
///
/// A shadow in SwiftUI follows the opacity of what casts it, and glass is
/// mostly see-through, so glass casts next to nothing. Casting from a solid
/// copy of the shape and cutting the inside away gives a full shadow around
/// the outside without darkening the glass itself.
package struct OuterShadow<S: Shape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    package init(shape: S, color: Color, radius: CGFloat, y: CGFloat) {
        self.shape = shape
        self.color = color
        self.radius = radius
        self.y = y
    }

    package var body: some View {
        GeometryReader { geo in
            let reach = radius * 3 + abs(y)
            shape
                .fill(Color.black)
                .shadow(color: color, radius: radius, x: 0, y: y)
                .mask(
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size).insetBy(dx: -reach, dy: -reach))
                        path.addPath(shape.path(in: CGRect(origin: .zero, size: geo.size)))
                    }
                    .fill(style: FillStyle(eoFill: true))
                )
        }
        .allowsHitTesting(false)
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
