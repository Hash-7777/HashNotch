import AppKit
import ApplicationServices
import HashNotchKit

/// Presses the keyboard's own media keys.
///
/// The last resort for controlling playback, and the only thing that reaches a
/// video in a browser. The system's media channel — the one every other source
/// goes through — reports success and does nothing for Safari: measured on a
/// playing video, pause returned true and the playback rate stayed at 1, then
/// play returned true and it stayed at 1. Browsers do not join that channel in
/// a way it can drive; they respond to the hardware keys.
///
/// Posting those keys is indistinguishable from pressing them, which is why
/// macOS gates it behind Accessibility. That is a real permission for a real
/// capability, so nothing here happens unless the user has switched it on.
package enum MediaKeys {
    /// NX_KEYTYPE_PLAY. There is no separate play and pause key on a keyboard —
    /// this one toggles, which is why the rest of the app avoids toggles and
    /// this path cannot. The app knows which state it is showing, so sending a
    /// toggle from a known state lands on the intended one; if it drifts, the
    /// next poll corrects the button rather than leaving it lying.
    package static let playPause: Int32 = 16
    package static let next: Int32 = 19
    package static let previous: Int32 = 20

    /// Whether macOS will currently let this app post those keys.
    ///
    /// Asked of `MediaControl` rather than of macOS directly. The settings
    /// window asks the same question through that type, and the two answers
    /// decide different halves of one behaviour — what the panel tells you
    /// about the permission, and whether a key is actually sent. Two copies of
    /// the same call can drift apart; one cannot.
    package static var isTrusted: Bool { MediaControl.hasPermission }

    /// Asks, once, with the system's own prompt — which offers to open the
    /// right pane rather than describing where it is.
    package static func requestTrust() {
        MediaControl.requestPermission()
    }

    /// Sends one press. Silently does nothing without permission — macOS drops
    /// the event, and there is nothing useful to report at that point because
    /// the user has already been asked.
    package static func press(_ key: Int32) {
        guard isTrusted else { return }
        for isDown in [true, false] {
            let data1 = Int((key << 16) | ((isDown ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
