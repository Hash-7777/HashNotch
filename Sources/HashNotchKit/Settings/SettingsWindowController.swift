import AppKit
import SwiftUI

/// The window settings live in: borderless, rounded, and hung beside the panel
/// rather than floating in the middle of the screen.
///
/// A titled window centred on the display was a different object from the thing
/// that opened it — you clicked a gear on the notch and a piece of ordinary Mac
/// furniture appeared somewhere else. Anchoring it to the panel keeps the two
/// as one surface, which is the whole idea the island is built on.
///
/// It can become key so the controls inside respond to the keyboard, which a
/// borderless window does not do by default.
final class SettingsPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the customization panel, and slides it out beside the island.
@MainActor
public final class SettingsWindowController {
    private let settings: SettingsStore
    private let descriptors: [FeatureDescriptor]
    private var window: SettingsPanelWindow?
    /// Which page to show. Held here rather than passed at open time, because
    /// the window and its view are built once and reused — a value the view is
    /// watching survives that, an argument to `show` would not.
    private let route = SettingsRoute()
    private var escapeMonitor: Any?
    private var outsideClickMonitor: Any?

    /// Told whenever the panel appears or disappears, so whatever it is
    /// attached to can stay open for as long as it is showing. Without this the
    /// island would collapse the moment the cursor left it to come here, and
    /// the settings would be left hanging beside nothing.
    public var onVisibilityChange: (Bool) -> Void = { _ in }

    /// Put this window AND the panel it belongs to away, together.
    ///
    /// Used when a setting is about to make macOS ask for something: the app's
    /// windows sit above the ordinary level, so a permission dialog can open
    /// behind them. Wired to the overlay, which is the only thing that can
    /// close both.
    public var onDismissAll: () -> Void = {}

    /// Wide enough for a full-width column of controls, narrow enough to sit
    /// beside the panel on a laptop display — there are only about 490 points
    /// to the right of the island on this size of screen, and a window that
    /// does not fit beside the thing it belongs to is not attached to anything.
    /// Tall enough that no page has to be scrolled.
    ///
    /// The width stayed at 460 when the page links moved from a column down the
    /// left to a strip across the top, because the goal was never a smaller
    /// window — it was giving the controls the 146 points the column was
    /// spending on six words.
    ///
    /// The height was 580, which fitted most pages and left Appearance and
    /// Indicators a little short — so those two scrolled, and a settings window
    /// that scrolls on some tabs and not others makes the reader wonder each
    /// time whether they have seen everything. 760 clears the longest page with
    /// room to spare; the frame below still shrinks it to fit a small display,
    /// so this is a ceiling rather than a demand.
    private static let size = CGSize(width: 460, height: 760)
    /// The gap between the island's edge and this one.
    private static let gap: CGFloat = 12
    /// How far it starts to the left of its resting place, so it reads as
    /// coming out from behind the island rather than fading in on the spot.
    private static let slideFrom: CGFloat = 26

    public init(settings: SettingsStore, registry: FeatureRegistry) {
        self.settings = settings
        self.descriptors = registry.features.map {
            FeatureDescriptor(id: $0.id, title: $0.title, options: $0.displayOptions)
        }
    }

    public var isVisible: Bool { window?.isVisible == true }

    /// Where it currently is on screen, or nil when it is not showing. The
    /// island asks so a click outside both it and the panel can put the pair
    /// away — and it has to be asked live, because the window can be dragged.
    public var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    /// Whether a click was delivered to this window.
    ///
    /// The island asks so that using settings is never mistaken for dismissing
    /// the panel settings belongs to. This answers by identity rather than by
    /// where the pointer was, so it cannot be defeated by the window being
    /// dragged, by a frame read mid-animation, or by a stale rectangle.
    public func owns(_ candidate: NSWindow?) -> Bool {
        guard let candidate, let window else { return false }
        return candidate === window
    }

    /// The gear is one button, so it is one button both ways.
    public func toggle(anchor: CGRect, on screen: NSScreen?) {
        isVisible ? hide() : show(anchor: anchor, on: screen)
    }

    /// Show it, and land on a particular page.
    ///
    /// Used when the island has just told somebody a switch is off: sending
    /// them to a window and letting them hunt for it is most of the way to not
    /// telling them at all.
    public func show(anchor: CGRect, on screen: NSScreen?, section: String) {
        route.requested = section
        show(anchor: anchor, on: screen)
    }

    public func show(anchor: CGRect, on screen: NSScreen?) {
        let window = window ?? makeWindow()
        self.window = window

        let visible = screen?.visibleFrame ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = Self.frame(besideAnchor: anchor, in: visible)
        // Start tucked behind the island and transparent, then travel out.
        var start = target
        start.origin.x -= Self.slideFrom
        window.setFrame(start, display: false)
        window.alphaValue = 0

        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange(true)
        beginWatchingForEscape()
        beginWatchingForOutsideClick()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            // Decelerating rather than eased both ends: it should leave the
            // island quickly and arrive gently, the way a drawer does.
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard let window, window.isVisible else { return }
        stopWatchingForEscape()
        stopWatchingForOutsideClick()

        var away = window.frame
        away.origin.x -= Self.slideFrom
        NSAnimationContext.runAnimationGroup { context in
            // Quicker going than coming. Leaving should not be something you
            // wait for.
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(away, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit runs this on the main thread, but the closure is typed
            // Sendable so the compiler cannot know that, and reaching
            // main-actor state from it is an error under Swift 6. Asserting
            // what AppKit already guarantees is the same pattern the hover and
            // scroll monitors use.
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self?.onVisibilityChange(false)
            }
        }
    }

    // MARK: Placement

    /// Where it sits: hung from the same top edge as the panel, just past its
    /// right side, and pulled back onto the display if there is not room —
    /// better to overlap the island slightly than to run off the screen.
    package static func frame(besideAnchor anchor: CGRect, in visible: CGRect) -> NSRect {
        let height = min(size.height, max(200, anchor.maxY - visible.minY - 24))
        var x = anchor.maxX + gap
        if x + size.width > visible.maxX - 12 {
            x = max(visible.minX + 12, visible.maxX - 12 - size.width)
        }
        return NSRect(x: x.rounded(), y: (anchor.maxY - height).rounded(), width: size.width, height: height)
    }

    // MARK: Plumbing

    private func makeWindow() -> SettingsPanelWindow {
        let window = SettingsPanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        // Above the menu bar, like the island it belongs to, and present on
        // whichever Space the user is on.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let root = SettingsView(
            settings: settings,
            features: descriptors,
            route: route,
            onDismissAll: { [weak self] in self?.onDismissAll() },
            onClose: { [weak self] in self?.hide() }
        )
        window.contentViewController = NSHostingController(rootView: root)
        return window
    }

    /// Escape closes it, which is the one keystroke everybody tries on a panel
    /// that has no title bar to close.
    private func beginWatchingForEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.hide() }
            return nil
        }
    }

    private func stopWatchingForEscape() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// A click anywhere else on screen puts it away, the way every popover on
    /// this system behaves.
    ///
    /// A GLOBAL monitor is exactly the right instrument, and for a reason worth
    /// writing down: global monitors never see this app's own events. So a
    /// click on the settings, or on the island's panel, simply does not arrive
    /// here — anything that does is by definition somewhere else, and there is
    /// no rectangle arithmetic to get wrong. It observes only; the click still
    /// reaches whatever it was aimed at.
    ///
    /// Closing also unpins the island, so the panel collapses behind it on the
    /// next mouse move, which is what makes one click outside dismiss the pair.
    private func beginWatchingForOutsideClick() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func stopWatchingForOutsideClick() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
