import AppKit

/// Finds a copy of this app still installed under a name it used to have.
///
/// This exists because of a fault that is invisible from the inside and reads,
/// to the person it happens to, as the app losing everything they set up.
///
/// Renaming a macOS app does not replace the old one. The two bundles have
/// different names, so both sit in Applications, and — the part nobody expects —
/// macOS records "open at login" against a bundle by **file reference, not by
/// path**. The registration therefore survives the rename and goes on opening
/// the OLD app at every login. That old build has its own bundle identifier and
/// so its own preferences domain, which means:
///
///   * the panel comes back with none of the settings that were chosen, because
///     those live in the other domain, and
///   * macOS asks for permissions again, because a different bundle identifier
///     is a different app as far as it is concerned.
///
/// Nothing has been lost, and nothing is broken — but there is no way to tell
/// that from the screen, and the obvious reading is that this app forgets itself
/// every time the Mac restarts. So it says so, plainly, rather than leaving
/// somebody to work it out.
///
/// Detection only. Nothing is deleted or unregistered on the user's behalf:
/// removing an app and clearing a login item are theirs to do, and a login-item
/// entry belongs to the bundle that registered it — this app cannot revoke
/// another bundle's registration even if it wanted to.
@MainActor
public enum PreviousInstall {
    /// Every bundle identifier this app has shipped under before the current
    /// one, so a copy under any of them can be recognised.
    ///
    /// The current identifier is deliberately NOT in here: this app is always
    /// installed, and finding itself is not a warning.
    public static let previousBundleIDs = ["com.hashdisland.app"]

    /// What was found, if anything: where the old copy is, and whether it is
    /// running right now.
    public struct Found: Equatable {
        public let bundleID: String
        public let url: URL
        public let isRunning: Bool

        public init(bundleID: String, url: URL, isRunning: Bool) {
            self.bundleID = bundleID
            self.url = url
            self.isRunning = isRunning
        }
    }

    /// The old copy on this Mac, if there is one.
    public static func find() -> Found? {
        for id in previousBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                continue
            }
            let running = !NSRunningApplication
                .runningApplications(withBundleIdentifier: id).isEmpty
            return Found(bundleID: id, url: url, isRunning: running)
        }
        return nil
    }

    /// Reveal the old app in Finder, so "delete it" points at something rather
    /// than asking somebody to go looking.
    public static func revealInFinder(_ found: Found) {
        NSWorkspace.shared.activateFileViewerSelecting([found.url])
    }

    /// Open the Login Items pane, which is where the leftover entry has to be
    /// removed by hand — deleting the app does not clear it.
    ///
    /// The modern pane first, falling back to the older one, because this app
    /// supports macOS 12 where Login Items still lives inside Users & Groups.
    public static func openLoginItems() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.users",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
