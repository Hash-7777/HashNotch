import AppKit
import SwiftUI

/// Asks before quitting.
///
/// The quit button sits in the panel's top band, a few points from the settings
/// gear and directly under where the pointer travels to reach the notch. It is
/// one click from "gone", with nothing to undo it and no Dock icon to click to
/// get the app back — the only way back is Spotlight or Finder, which is a lot
/// of work to pay for a slip of the hand.
///
/// So it asks. It asks in a window of the app's own, and **not** with
/// `NSAlert.runModal()`, which is what it used to do and why the button
/// appeared to be broken. `runModal` starts a nested run loop and does not
/// return until the question is answered, which for this app is fatal in three
/// separate ways at once:
///
///   * The main run loop is the island. Every animation, every sampler and
///     every mouse monitor stops for as long as the alert is up, so the panel
///     freezes half-shut instead of closing.
///   * The app is an agent (`LSUIElement`) whose only window refuses to become
///     key, so it is never the active app. `NSApp.activate` is a request, not a
///     guarantee, and when the system declined it the alert opened *behind*
///     whatever was in front — a modal question waiting for an answer where
///     nobody could see it.
///   * Between the two, the app looked hung and nothing quit. The button had in
///     fact worked; the question was simply somewhere off screen with the
///     island frozen behind it.
///
/// A plain window has none of that. It is drawn above the island, it joins
/// whichever Space is in front, the run loop keeps turning underneath it, and
/// the answer arrives as a callback rather than as a return value.
@MainActor
public final class QuitConfirmation {
    private var window: QuitPanelWindow?
    private let accent: () -> Color

    /// Called when the answer is yes, and only once the window is off screen —
    /// so nothing is left fading over the desktop as the app goes away.
    public var onQuit: () -> Void = { NSApp.terminate(nil) }

    /// The accent is read at the moment the question is asked rather than
    /// captured once, so the window matches the colour the island is wearing
    /// now rather than the one it wore at launch.
    public init(accent: @escaping () -> Color) {
        self.accent = accent
    }

    public var isVisible: Bool { window?.isVisible == true }

    /// Puts the question up. Asking twice while it is already showing brings the
    /// existing window forward instead of stacking a second one behind it.
    public func ask() {
        let window = self.window ?? makeWindow()
        self.window = window
        let hosting = NSHostingController(
            rootView: QuitConfirmationView(
                accent: accent(),
                onQuit: { [weak self] in self?.answerQuit() },
                onCancel: { [weak self] in self?.hide() }
            )
        )
        window.contentViewController = hosting
        // Exactly as tall as the words in it, measured rather than guessed.
        //
        // A hand-picked height has to be right for a sentence that wraps
        // differently at another text size or in another language, and when it
        // is too big the extra lands as a band of empty black between the last
        // line and the buttons — which reads as something having failed to draw.
        // `fittingSize` asks the laid-out view how much room it actually wants.
        //
        // Laid out first, because `fittingSize` reports on the arrangement that
        // exists when it is asked, and a view that has only just been attached
        // has not been arranged yet — the answer then is zero, and a window
        // sized from it is not small, it is invisible. The floor is the second
        // half of the same guard: whatever happens, this window is never
        // shrunk to something that cannot hold its own buttons.
        hosting.view.layoutSubtreeIfNeeded()
        let measured = hosting.view.fittingSize
        window.setContentSize(CGSize(
            width: Self.width,
            height: max(measured.height, Self.minimumHeight)
        ))
        if let screen = NotchGeometry.preferredScreen() ?? NSScreen.main {
            window.setFrameOrigin(Self.origin(for: window.frame.size, in: screen.visibleFrame))
        }
        if !window.isVisible { window.alphaValue = 0 }
        window.orderFrontRegardless()
        window.makeKey()
        // A request, not a guarantee — see the type's note. The window is drawn
        // above the island and ordered front regardless either way, so this only
        // decides whether it also comes forward of OTHER apps, never whether it
        // is on screen at all.
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
        }
    }

    private func answerQuit() {
        hide { [weak self] in self?.onQuit() }
    }

    /// Fade it out, and run `completion` once it is genuinely off screen.
    private func hide(then completion: @escaping () -> Void = {}) {
        guard let window, window.isVisible else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        }, completionHandler: {
            // AppKit runs this on the main thread, but the closure is typed
            // Sendable so the compiler cannot know that. Same pattern as the
            // first-run window's fade.
            MainActor.assumeIsolated {
                window.orderOut(nil)
                completion()
            }
        })
    }

    /// Wide enough for the sentence to break where it reads well, and no wider
    /// — this is a question, not a document.
    package static let width: CGFloat = 420
    /// The least the window may ever be, whatever a measurement says. Enough for
    /// the title, one line, and the buttons.
    package static let minimumHeight: CGFloat = 150

    /// Where the window sits: the middle of the screen the island is on.
    ///
    /// **Not `NSWindow.center()`.** Despite the name, that method does not
    /// centre a window vertically — it places it high, leaving about a third of
    /// the free space above it. On a laptop screen that put this window up under
    /// the physical notch, hard against the top bezel, right beside the island
    /// whose button had just raised it. The two then read as one thing, which is
    /// the opposite of what closing the panel first was for: this question is
    /// about the whole app, so it belongs where the eye already is.
    ///
    /// Measured against `visibleFrame` rather than `frame`, so the menu bar and
    /// the Dock are excluded and the middle is the middle of the space actually
    /// available.
    ///
    /// Pure and package-visible: "centred" is a claim about arithmetic, and this
    /// is the arithmetic that was wrong.
    package static func origin(for size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
    }

    private func makeWindow() -> QuitPanelWindow {
        let window = QuitPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minimumHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Draggable by its background: there is no title bar to grab, and
        // these open over whatever is being worked on. Set rather than
        // overridden — AppKit reads its own stored value here, so a computed
        // override is not reliably consulted.
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Above the island, or it is not a question — it is a hidden one. The
        // overlay floats at `.statusBar` so it can draw over the menu bar, and
        // anything lower than that opens underneath the very panel whose button
        // asked. The first-run window can sit at `.modalPanel` because it is the
        // only thing on screen; this one is answered with the island still up.
        window.level = .popUpMenu
        // Whichever Space is in front. An agent app has no Space of its own, so
        // without this the question can open on the desktop the user came from.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}

/// Borderless, but it must take the keyboard so Return and Escape work on the
/// buttons and the window reads as the thing being answered rather than a
/// picture of one.
/// Draggable by its background, because it has no title bar to grab.
///
/// A borderless window is immovable by default, and these are windows somebody
/// may well want out of the way — they open in the middle of the screen, over
/// whatever is being worked on, and there is no edge to take hold of. Turning
/// this on makes any part of the surface that is not a control a place to drag
/// from, which is the whole title bar's job on an ordinary window.
final class QuitPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The question itself, in the same hand as the first-run window: a dark HUD
/// surface, a plain sentence, and the two answers at the bottom.
package struct QuitConfirmationView: View {
    package let accent: Color
    package let onQuit: () -> Void
    package let onCancel: () -> Void

    package init(accent: Color, onQuit: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.accent = accent
        self.onQuit = onQuit
        self.onCancel = onCancel
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Self.destructive)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Self.destructive.opacity(0.14))
                        )
                    Text("Quit HashNotch?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                }
                // Drag the panel by its heading, the way a title bar works.
                // Laid over the icon and the words, which have nothing to
                // click, so the buttons below are untouched.
                .overlay(WindowDragArea())
                Text("The island will disappear from your notch. Everything it was watching stops, and nothing else on your Mac is affected.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                Text("To bring it back, open HashNotch again from Applications.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            actions
        }
        // Width only. The height is whatever the words need — see the note on
        // `fittingSize` where the window is sized. A `Spacer` used to sit above
        // the hairline to fill a fixed 236 points, which is the same mistake
        // said twice: the view padded itself out to a number, and the window
        // was told that number separately.
        .frame(width: QuitConfirmation.width)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow)
                Color.black.opacity(0.55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Red, so the button that ends the app never looks like the safe one — the
    /// same red the power button in the panel is drawn in.
    private static let destructive = Color(red: 1.0, green: 0.35, blue: 0.35)

    /// Escape backs out, which is the reflex when a window appears by accident
    /// — and appearing by accident is the case this exists for. Return quits,
    /// which is what the system alert this replaced did, so a hand that already
    /// knows the answer is not made to reach for the mouse.
    private var actions: some View {
        HStack(spacing: 12) {
            Button("Cancel") { onCancel() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Quit") { onQuit() }
                .buttonStyle(.borderedProminent)
                .tint(Self.destructive)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
