import CoreMediaIO
import Foundation

/// Whether any camera is capturing right now.
///
/// The same question `CallReader` asks about the microphone, asked about the
/// camera, and answered the same way: one boolean per device. No video is
/// opened, no frame is read, nothing is recorded or looked at, and the app holds
/// no camera permission — reading this flag is not using the camera, in the same
/// way that seeing a door is shut is not going through it. Measured: this reads
/// successfully with no camera permission and no prompt, returns false with
/// every camera idle, and turns true within a second of an app opening one.
///
/// ## What it can say, and what it deliberately cannot
///
/// CoreAudio publishes a list of *processes* holding an input stream, which is
/// how the microphone readout can name the app. CoreMediaIO publishes nothing of
/// the kind. What exists is per *device* — is this camera running somewhere — so
/// a camera can be reported as live, truthfully, but cannot be attributed on its
/// own.
///
/// That is the whole reason this is folded into the microphone readout rather
/// than being an indicator of its own. When something holds both, the microphone
/// names the app and the camera joins the same row. When only the camera is
/// live, the row says so and names nobody — the same honest answer the
/// microphone already gives when a background service holds it. Guessing that
/// the camera belongs to whichever app last held the microphone would be right
/// most of the time, and this file does not guess: naming the wrong app on a row
/// about being watched is worse than naming none.
package enum CameraReader {
    /// True when at least one camera on this Mac is running.
    package static func isCapturing() -> Bool {
        capturingCount() > 0
    }

    /// How many cameras are running. Package-visible so the checks can see that
    /// a machine with nothing recording reports none.
    package static func capturingCount() -> Int {
        devices().filter(isRunning).count
    }

    /// How many cameras this Mac has at all, running or not. Also for the
    /// checks: a reader that found no devices would answer "no camera in use"
    /// forever and look exactly like one that worked.
    package static func deviceCount() -> Int {
        devices().count
    }

    /// Nothing here reads a camera's NAME. It would cost a CFString to manage
    /// and buy nothing: the readout never says which camera, because which
    /// camera is not the question anybody is asking of it.
    ///
    /// Every camera object the system knows about. Deliberately not asking for
    /// screen-capture devices (`kCMIOHardwarePropertyAllowScreenCaptureDevices`),
    /// which is opt-in and stays off: this readout is about a camera pointed at
    /// you.
    private static func devices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size
        ) == 0, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var objects = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &objects
        ) == 0 else { return [] }
        return objects
    }

    /// The one question this file exists to ask.
    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &size) == 0, size > 0
        else { return false }
        var running: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == 0
        else { return false }
        return running != 0
    }
}
