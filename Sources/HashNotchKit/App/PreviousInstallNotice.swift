import AppKit
import SwiftUI

/// Tells somebody that an older copy of this app, under its previous name, is
/// still installed — and that it is the one opening at login.
///
/// See `PreviousInstall` for why this is worth a window rather than a line in a
/// release note. The symptom is "the app lost all my settings and asks for
/// permissions every time I restart", which sounds like a broken app and gives
/// no hint at all that the cause is a second bundle sitting in Applications.
/// Somebody who never reads a changelog still has to be able to find out.
///
/// Shown once per launch while the old copy is there, and never again once it
/// has gone. That is deliberately not a setting: this app is normally opened at
/// login, so "once per launch" is in practice once per restart — which is
/// exactly when the confusion happens — and it stops for good the moment the
/// thing it is about is dealt with.
@MainActor
public final class PreviousInstallNotice {
    private var window: NoticePanelWindow?
    private let accent: () -> Color

    public init(accent: @escaping () -> Color) {
        self.accent = accent
    }

    public var isVisible: Bool { window?.isVisible == true }

    /// Put the notice up for a copy that was found.
    public func show(_ found: PreviousInstall.Found) {
        let window = self.window ?? makeWindow()
        self.window = window
        let hosting = NSHostingController(
            rootView: PreviousInstallNoticeView(
                accent: accent(),
                isRunning: found.isRunning,
                onReveal: { PreviousInstall.revealInFinder(found) },
                onLoginItems: { PreviousInstall.openLoginItems() },
                onDismiss: { [weak self] in self?.hide() }
            )
        )
        window.contentViewController = hosting
        // Measured, not guessed — and laid out first, because a view that has
        // not been arranged reports zero and a window sized from zero is not
        // small, it is invisible. Same reasoning as the quit window.
        hosting.view.layoutSubtreeIfNeeded()
        let measured = hosting.view.fittingSize
        window.setContentSize(CGSize(
            width: Self.width,
            height: max(measured.height, Self.minimumHeight)
        ))
        if let screen = NotchGeometry.preferredScreen() ?? NSScreen.main {
            window.setFrameOrigin(
                QuitConfirmation.origin(for: window.frame.size, in: screen.visibleFrame)
            )
        }
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { window.orderOut(nil) }
        })
    }

    package static let width: CGFloat = 480
    package static let minimumHeight: CGFloat = 200

    private func makeWindow() -> NoticePanelWindow {
        let window = NoticePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.minimumHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}

/// Borderless, but it takes the keyboard so Escape closes it.
final class NoticePanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The words. Written to be read by somebody who has just watched their
/// settings apparently vanish, so the first thing it says is that they have not.
struct PreviousInstallNoticeView: View {
    let accent: Color
    let isRunning: Bool
    let onReveal: () -> Void
    let onLoginItems: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(accent.opacity(0.14))
                        )
                    Text("The old app is still on this Mac")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

                Text("Your settings are safe. Nothing has been lost.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                Text(explanation)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Drag the old Hash D Island app to the Trash.")
                    step(2, "In System Settings, open General \u{2192} Login Items and remove any Hash D Island entry with the minus button. Deleting the app does not clear it.")
                }
                .padding(.top, 2)
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
        .frame(width: PreviousInstallNotice.width)
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

    /// Said differently depending on whether the old app is up right now, so it
    /// describes what is actually on screen rather than a generality.
    private var explanation: String {
        let common = "It keeps its own separate settings and asks for its own permissions, so whenever it opens instead of this one, the notch looks like it has forgotten everything you chose."
        return isRunning
            ? "An older version of this app, from when it was called Hash D Island, is running right now. " + common
            : "An older version of this app, from when it was called Hash D Island, is still installed. macOS remembers \u{201C}open at login\u{201D} against that one, so it can start instead of this one. " + common
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Later") { onDismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Open Login Items") { onLoginItems() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))

            Button("Show me the old app") { onReveal() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
