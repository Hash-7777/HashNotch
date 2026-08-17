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
        window.contentViewController = NSHostingController(
            rootView: QuitConfirmationView(
                accent: accent(),
                onQuit: { [weak self] in self?.answerQuit() },
                onCancel: { [weak self] in self?.hide() }
            )
        )
        window.center()
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

    private func makeWindow() -> QuitPanelWindow {
        let window = QuitPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 236),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
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
final class QuitPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The question itself, in the same hand as the first-run window: a dark HUD
/// surface, a plain sentence, and the two answers at the bottom.
struct QuitConfirmationView: View {
    let accent: Color
    let onQuit: () -> Void
    let onCancel: () -> Void

    var body: some View {
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
                    Text("Quit Hash D Island?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                Text("The island will disappear from your notch. Everything it was watching stops, and nothing else on your Mac is affected.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                Text("To bring it back, open Hash D Island again from Applications.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Spacer(minLength: 0)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            actions
        }
        .frame(width: 420, height: 236)
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
