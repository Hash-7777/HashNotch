import AppKit
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for "open at login".
///
/// This only takes effect when HashNotch runs as a proper `.app` bundle (see
/// scripts/build_app.sh); from a bare `swift run` binary the register call is a
/// no-op that throws, which callers treat as "not available yet".
///
/// ## Older macOS
///
/// `SMAppService` arrived in macOS 13. Below that the only supported way to be
/// a login item was a bundled helper app registered through
/// `SMLoginItemSetEnabled` — a second executable inside this one, with its own
/// signing and its own lifecycle, for a checkbox. That is a large amount of
/// machinery and a second thing to keep signed, and it is deprecated on every
/// system that can run it.
///
/// So on macOS 12 the feature reports itself unsupported and the switch
/// explains why, which is the honest version of not having it: the setting is
/// visibly unavailable with a reason, rather than present and silently doing
/// nothing. Everything else in the app is unaffected.
public enum LoginItem {
    /// Whether this macOS can manage login items the modern way at all.
    public static var isAvailableOnThisSystem: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    public static var isEnabled: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Whether this copy is even able to be a login item.
    ///
    /// Asked of the BUNDLE, not of the registration. It used to be
    /// `status != .notFound`, and `.notFound` is precisely what an app that has
    /// never been registered reports — which is the state everybody is in
    /// before they switch it on. So the switch was disabled for exactly the
    /// people trying to use it, explaining that the feature would be available
    /// once the app was installed as an app, while running as an installed app.
    /// Nothing else registers it, so it could never become available.
    ///
    /// macOS manages login items by bundle, so being a bundle is the whole
    /// requirement: a bare `swift run` binary has no identifier and cannot,
    /// an installed `.app` can.
    public static var isSupported: Bool {
        isAvailableOnThisSystem
            && Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Why the switch is unavailable, when it is. Nil when it works.
    public static var unavailableReason: String? {
        if !isAvailableOnThisSystem {
            return "Opening at login needs macOS 13 or later."
        }
        if Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app" {
            return "Available once HashNotch is installed as an app."
        }
        return nil
    }

    /// The user has been asked and has not said yes yet. macOS parks the
    /// request in System Settings rather than prompting, so an app that does
    /// not mention this leaves the switch looking simply broken.
    public static var needsApproval: Bool {
        guard #available(macOS 13, *) else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Opens the pane where a parked request is approved.
    public static func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Say why. This used to fail in silence, so the switch simply
            // sprang back and there was nothing anywhere to explain it —
            // which is the least helpful way for a permission-shaped failure
            // to behave.
            FileHandle.standardError.write(Data(
                "HashNotch: could not \(enabled ? "register" : "unregister") the login item — \(error)\n".utf8
            ))
            return false
        }
    }

    /// What the system currently thinks, in words.
    package static var statusDescription: String {
        guard #available(macOS 13, *) else { return "unavailableOnThisSystem" }
        switch SMAppService.mainApp.status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}
