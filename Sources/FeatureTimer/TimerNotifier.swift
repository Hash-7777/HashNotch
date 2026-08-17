import AppKit
import UserNotifications

/// Alerts the user when the timer ends: a retained system chime that actually
/// plays (a throwaway NSSound is deallocated before it sounds), plus a native
/// notification banner — the same kind of finish alert HashCerebrum posts.
///
/// Notifications need a bundled, identified app; the raw dev binary
/// (`swift run`) has no bundle id, so there the chime is the whole alert and
/// the notification calls are skipped instead of crashing.
final class TimerNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var chime: NSSound?

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Ask once, early (on timer start), so the banner can appear the moment
    /// the timer ends without a permission prompt racing the alert.
    func requestAuthorization() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Play the chime and post the banner.
    func fire(title: String, body: String) {
        // Retain the sound for its lifetime so it is not collected mid-play.
        let sound = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping"))
        sound?.stop()
        sound?.play()
        chime = sound

        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The chime already sounds; keep the banner silent so it does not
        // double up.
        let request = UNNotificationRequest(
            identifier: "com.hashnotch.timer.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Show the banner even though HashNotch is running (an agent app is never
    /// "frontmost", but this makes the intent explicit).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
