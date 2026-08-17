import AppKit
import SwiftUI

/// Owns the window a new install sees before any feature starts.
///
/// Centred rather than hung beside the notch, unlike settings. Settings is
/// attached to the panel because it edits it; this is not about the panel — it
/// is the one thing on screen, asked once, and it should be where the eye
/// already is rather than tucked against the top edge where a new user has not
/// yet learned to look.
@MainActor
public final class FirstRunWindowController {
    private let settings: SettingsStore
    private var window: FirstRunPanelWindow?

    /// Called when the user accepts, and only once this window has actually
    /// left the screen. Whoever owns this starts the features.
    ///
    /// The order matters and it used to be wrong. Accepting starts the
    /// indicators, and starting them is what makes macOS raise its own
    /// permission prompt for the Downloads folder — so calling back while this
    /// window was still fading put a system prompt on top of the window that
    /// had just asked for permission itself. Two consent dialogs stacked on each
    /// other, the second one appearing to answer the first. The window goes
    /// first, then anything it triggered.
    public var onAccept: () -> Void = {}

    /// Called when the user refuses, once this window has left the screen.
    /// Whoever owns this quits the app — nothing has read anything, and there
    /// is nothing to undo.
    public var onDecline: () -> Void = {}

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var isVisible: Bool { window?.isVisible == true }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
        }
    }

    /// Fade it out, and run `completion` once it is genuinely off screen.
    ///
    /// Not merely once it has been asked to go: the fade takes 0.16s and the
    /// window is on screen for every millisecond of it. Anything that puts up
    /// another window has to wait for this one to be gone, or it lands on top
    /// of it.
    public func hide(then completion: @escaping () -> Void = {}) {
        guard let window, window.isVisible else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        }, completionHandler: {
            // AppKit runs this on the main thread, but the closure is typed
            // Sendable so the compiler cannot know that. Same pattern as the
            // settings window's own fade.
            MainActor.assumeIsolated {
                window.orderOut(nil)
                completion()
            }
        })
    }

    private func makeWindow() -> FirstRunPanelWindow {
        let window = FirstRunPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = FirstRunView(
            accent: settings.accent.color,
            onAccept: { [weak self] in
                guard let self else { return }
                self.hide(then: { [weak self] in self?.onAccept() })
            },
            onDecline: { [weak self] in
                guard let self else { return }
                self.hide(then: { [weak self] in self?.onDecline() })
            }
        )
        window.contentViewController = NSHostingController(rootView: root)
        return window
    }
}

/// Borderless, but it must take the keyboard so Return works on the button and
/// the window reads as the thing being answered rather than a picture of one.
final class FirstRunPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
