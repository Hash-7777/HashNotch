import Foundation

/// What macOS says about opening at login, read once and kept.
///
/// `SMAppService.status` is a synchronous round trip to the system's own
/// service-management daemon. It is usually a couple of milliseconds, and it is
/// not always: sampled in the running app while the settings window was in use,
/// single calls took 89, 41 and 112 ms, and the whole window is frozen for
/// every one of those milliseconds because they happen while a view is being
/// drawn on the main thread.
///
/// The General page asked three times each time it drew — is it supported, is
/// it on, is it waiting for approval — and SwiftUI draws a page more than once
/// per change. That is what made switching to it feel like the window had
/// hung.
///
/// So it is asked off the main thread, once, and the answer is kept: when the
/// window opens, and again after the switch is used, which is the only thing
/// inside this app that can change it. A stale answer is not possible from in
/// here; one made outside — in System Settings — is picked up the next time
/// the window is opened.
@MainActor
public final class LoginItemStatus: ObservableObject {
    /// Whether the app is registered to open at login.
    @Published public private(set) var isEnabled = false
    /// Whether macOS has parked the request in System Settings.
    @Published public private(set) var needsApproval = false

    /// Whether this copy can be a login item at all. A bundle question, not a
    /// daemon one — free to ask, so it is not cached.
    public nonisolated var isSupported: Bool { LoginItem.isSupported }

    /// Why the switch is unavailable, when it is. Also free.
    public nonisolated var unavailableReason: String? { LoginItem.unavailableReason }

    /// The slow question, kept behind a closure so it can be counted.
    private let read: @Sendable () -> (enabled: Bool, needsApproval: Bool)
    private let queue = DispatchQueue(label: "com.hashnotch.loginitem", qos: .userInitiated)

    public init(
        read: @escaping @Sendable () -> (enabled: Bool, needsApproval: Bool) = {
            (LoginItem.isEnabled, LoginItem.needsApproval)
        }
    ) {
        self.read = read
    }

    /// Ask macOS, off the main thread, and keep the answer.
    public func refresh() {
        guard isSupported else {
            isEnabled = false
            needsApproval = false
            return
        }
        let read = self.read
        // Weak on the OUTER closure. An inner `[weak self]` would be undone by
        // the outer one having already captured self strongly to hand it on.
        queue.async { [weak self] in
            let answer = read()
            Task { @MainActor in
                guard let self else { return }
                self.isEnabled = answer.enabled
                self.needsApproval = answer.needsApproval
            }
        }
    }
}
