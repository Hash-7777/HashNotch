import ApplicationServices

/// The permission the panel's media buttons need to reach a browser.
///
/// Lives in the core rather than in the media module because the settings
/// window has to ask for it, and settings knows nothing about features.
public enum MediaControl {
    /// Whether macOS will let this app press the media keys.
    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Asks with the system's own prompt, which offers to open the right pane.
    /// Called when the switch is turned on and at no other time.
    public static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
