import AppKit
import UserNotifications

/// Tells the person their timer is up, and is honest about whether it can.
///
/// **Why the alert is scheduled rather than fired.** It used to be posted at
/// the moment the app itself noticed the countdown reach zero, which means the
/// alert could only ever be as punctual as the app was awake. The app stops
/// sampling when the display sleeps — deliberately, it is the single biggest
/// saving there is — so the one moment a timer most needs to be heard is a
/// moment when nothing here is running. Handing the deadline to the system
/// instead makes the alert the system's job: it lands on time whether the
/// display is asleep, the panel is shut, this app is busy, or this app has been
/// quit.
///
/// **Why the app then goes quiet.** With the system delivering the alert, a
/// chime here as well would be two alerts for one timer — and worse, a second
/// one at the wrong moment, since the app's notice of the finish can be
/// minutes late while the system's is not. So there is exactly one alert, and
/// which one it is depends on a fact rather than a guess: if the system will
/// show a banner, it makes the noise and this makes none; if it will not, this
/// chimes and the panel says so. `swift run` has no bundle identifier and can
/// hold no notification permission at all, so there the chime is the whole
/// alert.
@MainActor
final class TimerNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// One identifier, so a scheduled alert can be taken back exactly.
    ///
    /// Not a fresh UUID per timer, which is what this used to do: an
    /// unrepeatable identifier is one nothing can ever cancel, and a cancelled
    /// timer that still goes off at the original moment is worse than no timer.
    static let requestIdentifier = "com.hashnotch.timer.deadline"

    /// What the system last said about showing a banner. `nil` until asked.
    private(set) var isAllowed: Bool?

    /// Called whenever that answer changes, so the panel can stop promising
    /// something that will not happen.
    var onAllowedChanged: (Bool?) -> Void = { _ in }

    private var chime: NSSound?

    /// Notifications need a bundled, identified app. The raw development binary
    /// has no bundle id, so the calls are skipped rather than made and failed.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Ask once, when a timer is started, and find out what was actually
    /// granted.
    ///
    /// The answer used to be thrown away — `requestAuthorization` was called
    /// with an empty handler — so an app that had been refused went on
    /// behaving exactly as if it had been allowed, and the person who refused
    /// got no banner, no chime and no explanation. Asking every time a timer
    /// starts also catches permission being withdrawn later, which the first
    /// answer cannot.
    func prepare(then settled: @escaping () -> Void = {}) {
        guard isBundled else {
            update(nil)
            settled()
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            // Asked for again rather than captured: the centre is a single
            // shared object and carrying it into a background closure is a
            // capture the compiler is right to object to.
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let allowed = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                Task { @MainActor [weak self] in
                    self?.update(allowed)
                    settled()
                }
            }
        }
    }

    /// Hand the deadline to the system, so it lands on time whatever this app
    /// is doing.
    /// Returns whether the system took it, so the deadline can record that an
    /// alert exists somewhere other than in this process.
    @discardableResult
    func schedule(at date: Date, title: String, body: String) -> Bool {
        // Never claimed when the answer is known to be no: the request would be
        // added and quietly never delivered, and the deadline would go on
        // record as one the system is taking care of — which is what decides
        // whether the app makes its own noise later.
        guard isBundled, isAllowed != false else { return false }
        cancelScheduled()
        let seconds = date.timeIntervalSinceNow
        // A trigger has to be in the future. Anything already due is not
        // scheduled at all: the app is awake and looking at it, and it will say
        // so itself.
        guard seconds > 0.5 else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The system makes the noise, because the system is the one that will
        // be awake.
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
        return true
    }

    /// Take back an alert for a timer that is no longer running.
    func cancelScheduled() {
        guard isBundled else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }

    /// The alert for when the system will not be making one.
    ///
    /// Retained for its lifetime: a throwaway `NSSound` is collected before it
    /// has finished sounding, which is silence with no error anywhere.
    func chimeNow() {
        let sound = NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping"))
        sound?.stop()
        sound?.play()
        chime = sound
    }

    private func update(_ allowed: Bool?) {
        guard allowed != isAllowed else { return }
        isAllowed = allowed
        onAllowedChanged(allowed)
    }

    /// Show the banner even though HashNotch is running — an agent app is never
    /// "frontmost", but this makes the intent explicit — and let it sound,
    /// since it is the only alert there is.
    ///
    /// Outside the main actor because it touches nothing of this object's:
    /// it answers with two constants. Isolating it would make the whole
    /// conformance cross an actor boundary for the sake of a reply that needs
    /// no state at all.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
