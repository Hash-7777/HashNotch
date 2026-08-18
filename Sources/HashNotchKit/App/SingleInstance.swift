import AppKit

/// Refuses to be two islands.
///
/// Everything this app draws is drawn once per running copy: one overlay, one
/// strip, one notice per post. So a second copy does not add a second app so
/// much as double the first — every "finished" alert appears twice, on top of
/// itself, and the only sign that anything is wrong is that the notch is saying
/// everything twice.
///
/// A second copy is easier to end up with than it sounds. The app has no Dock
/// icon and no menu-bar item, so there is nothing on screen to say it is
/// already running: a build folder copy and an Applications copy are two
/// different files as far as Launch Services is concerned, and opening either
/// while the other is up starts a second one. Nothing about the result looks
/// like two apps.
///
/// Asked of the bundle identifier rather than the executable path, because the
/// two copies are the same app — that is the whole point — and the path is
/// exactly what differs between them.
public enum SingleInstance {
    /// Other running copies of this same app, if any.
    ///
    /// Never counts this process itself. `runningApplications(withBundleIdentifier:)`
    /// includes the caller, so a straight count is always at least one and a
    /// check written against it refuses to start the FIRST copy.
    public static func others() -> [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != mine }
    }

    /// Whether another copy is already up.
    ///
    /// False when the app is unbundled — a raw `swift run` build has no bundle
    /// identifier, cannot be recognised, and is how the app is worked on. It
    /// must never refuse to start there.
    public static var anotherCopyIsRunning: Bool {
        Bundle.main.bundleIdentifier != nil && !others().isEmpty
    }

    /// Bring the copy that was already running to the front, so opening the app
    /// a second time does something rather than appearing to do nothing.
    ///
    /// There is no window to raise — the island is an overlay that never takes
    /// focus — so this is a best effort and deliberately not relied upon.
    public static func activateExistingCopy() {
        others().first?.activate()
    }
}
