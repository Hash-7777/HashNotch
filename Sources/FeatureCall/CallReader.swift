import AppKit
import CoreAudio
import Darwin
import Foundation

/// Which app, if any, currently has the microphone open.
///
/// ## What this does and does not do
///
/// It asks CoreAudio one question: *is this process running an input stream?*
/// The answer is a boolean. No audio is opened, no samples are read, nothing is
/// recorded, transcribed or inspected, and no microphone permission is asked
/// for or held — reading this flag is not using the microphone, in the same way
/// that seeing a door is shut is not going through it.
///
/// That is the entire mechanism, and it is worth being precise about because
/// "the app knows when you are on a call" is exactly the sentence that should
/// make somebody suspicious. What it knows is that an application has an input
/// stream open. It does not know who you are talking to, whether anybody is
/// talking, or what is being said, and there is nothing in this file that could
/// be extended to find out — the API returns a flag and a process id.
///
/// ## Which app
///
/// The process id is turned into a running application, which gives the name
/// and the icon. Only real applications count: `corespeechd`, Apple's own
/// dictation service, holds an input stream open permanently on a normal Mac,
/// and every other system daemon is free to do the same. A helper with no
/// bundle identifier is not something a person is "in a call" with, so the
/// filter is for an actual app rather than a list of meeting apps by name —
/// FaceTime, Zoom, Teams, Meet in a browser, a game, a voice recorder, or
/// something released next year all work identically, and nothing has to be
/// added to a list for a new one to be recognised.
///
/// The process holding the input is often not the one a person is looking at.
/// A browser does not open the microphone in the process you can see: in a
/// meeting in Safari the input belongs to `com.apple.WebKit.GPU`, which macOS
/// names "Safari Graphics and Media" and which carries no icon of its own. Left
/// alone, the readout said exactly that, beside an empty placeholder — a true
/// statement about the machine, and one that reads to anybody looking at it as
/// a program they have never heard of listening to their interview.
///
/// So every holder is resolved to the application it belongs to before anything
/// is said about it. See `owningApplication(of:)`.
package enum CallReader {
    /// One app with the microphone open.
    package struct Listener: Equatable {
        package let bundleIdentifier: String
        package let name: String
        package let processID: pid_t
        /// False when the microphone is held by a background service rather
        /// than by something the user would recognise, and no app could be
        /// attributed. The readout then says a microphone is in use without
        /// naming anything, which is the honest answer.
        package var isNamedApp: Bool = true

        package init(
            bundleIdentifier: String,
            name: String,
            processID: pid_t,
            isNamedApp: Bool = true
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.processID = processID
            self.isNamedApp = isNamedApp
        }
    }

    /// Apple's own audio services, and the app each one works for.
    ///
    /// A list of one, and it is here reluctantly — naming things by identifier
    /// is what this file otherwise avoids, because a list is wrong for
    /// everything not on it. It exists because FaceTime does not hold the
    /// microphone itself: `avconferenced`, a daemon, holds it on FaceTime's
    /// behalf, so the readout said "avconferenced" during a FaceTime call. That
    /// is a true statement about the machine and a useless one about the call.
    ///
    /// Every other app tested holds its own input — Zoom, Teams, a browser, a
    /// voice memo — so nothing else needs an entry, and anything that does show
    /// up through a daemon nobody has mapped is reported as an unnamed
    /// microphone rather than by its internal name.
    private static let serviceOwners: [String: String] = [
        "com.apple.avconferenced": "com.apple.FaceTime",
    ]


    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// The app using the microphone right now, or nil.
    ///
    /// When more than one is, the frontmost wins — on the rare occasion two
    /// apps hold input at once, the one being looked at is the one the notch
    /// should be about.
    package static func current() -> Listener? {
        let listeners = allListeners()
        guard !listeners.isEmpty else { return unattributedIfInputRunning() }

        // An app somebody would recognise, once each holder has been resolved
        // to the application it belongs to. That resolution is what turns
        // "Safari Graphics and Media" into Safari, and it also fixes the line
        // below: the frontmost app's process id could never match a helper's,
        // so the rule about two apps at once had nothing to compare.
        //
        // Several helpers of one app can hold input at the same time — a
        // browser in a meeting easily has two — so an app is listed once.
        let apps = distinct(listeners.compactMap(attributed))
        if !apps.isEmpty {
            if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               let match = apps.first(where: { $0.processID == front }) {
                return match
            }
            return apps.first
        }

        // Otherwise a background service has it. Attribute it to the app it
        // serves where that is known and that app is actually running —
        // FaceTime being the case this exists for.
        for listener in listeners {
            guard let ownerID = serviceOwners[listener.bundleIdentifier],
                  let owner = NSRunningApplication
                      .runningApplications(withBundleIdentifier: ownerID).first,
                  let name = owner.localizedName
            else { continue }
            return Listener(
                bundleIdentifier: ownerID,
                name: name,
                processID: owner.processIdentifier
            )
        }

        // Something has the microphone and nothing here can honestly say what.
        // Still worth showing — that the microphone is live is the important
        // half — but named as what it is rather than by a daemon's internal
        // name, which tells the reader nothing and looks like a bug.
        return Listener(
            bundleIdentifier: listeners[0].bundleIdentifier,
            name: "Microphone in use",
            processID: listeners[0].processID,
            isNamedApp: false
        )
    }

    /// The last resort: the input device says it is running, but no process the
    /// app can see owns it.
    ///
    /// This is what dictation looks like. macOS runs it through `corespeechd`,
    /// which has no bundle identifier at all and so never appears as an app —
    /// and which holds an input stream open PERMANENTLY on an ordinary Mac, so
    /// its own flag says nothing about whether anybody is dictating. Measured:
    /// idle, with corespeechd holding input, the device still reported itself
    /// as not running.
    ///
    /// So the two answer different questions. The per-process list answers WHO,
    /// and the device flag answers WHETHER — and when the second says yes while
    /// the first has nobody to offer, the honest readout is that the microphone
    /// is live with no name attached.
    private static func unattributedIfInputRunning() -> Listener? {
        guard inputBusyDeviceWide() else { return nil }
        return Listener(
            bundleIdentifier: "",
            name: "Microphone in use",
            processID: 0,
            isNamedApp: false
        )
    }

    /// Whether a process is an application in its own right, rather than a
    /// piece of one.
    ///
    /// Stated as a rule over two facts, apart from the live lookup, so it can
    /// be checked: the cases that matter are helpers, and a helper cannot be
    /// conjured on demand inside a check.
    ///
    /// Both halves are needed, and the second is the one that was missing.
    /// `.prohibited` excludes a daemon — there is nothing to bring to the front
    /// — but it does not exclude an XPC service, which is `.accessory` for the
    /// same reason a menu-bar app is. What separates those two is where they
    /// live. An application is a `.app` bundle; a piece of one is a `.xpc`
    /// bundle inside a framework or inside an app, or has no bundle at all.
    ///
    /// Measured on macOS 15: `com.apple.WebKit.GPU` is `.accessory`, its bundle
    /// is `…/WebKit.framework/…/XPCServices/com.apple.WebKit.GPU.xpc`, and
    /// `com.apple.WebKit.WebContent` reports no bundle URL whatsoever.
    package static func isApplication(bundleExtension: String?, isProhibited: Bool) -> Bool {
        bundleExtension == "app" && !isProhibited
    }

    private static func isApplication(_ app: NSRunningApplication) -> Bool {
        isApplication(
            bundleExtension: app.bundleURL?.pathExtension,
            isProhibited: app.activationPolicy == .prohibited
        )
    }

    /// `responsibility_get_pid_responsible_for_pid`, if this macOS has it.
    ///
    /// This is the same question the system asks itself. When Safari's graphics
    /// process opens the microphone, the orange dot in the menu bar says
    /// Safari, because macOS attributes a helper to the application it was
    /// started for — and it is the only thing that can, since the helper's
    /// bundle sits in WebKit's framework rather than in Safari, and its parent
    /// process is `launchd` rather than Safari. Neither the path nor the
    /// process tree leads back to the app; this does.
    ///
    /// Nothing public exposes that answer, so the symbol is looked up by name
    /// once, at runtime, and the app simply does without it if it is ever
    /// withdrawn: an unattributable holder falls through to being reported as a
    /// microphone in use with no name on it, which is less useful and still
    /// true. That is the reason this is a lookup rather than a declaration —
    /// a missing symbol must not be a launch failure.
    ///
    /// The handle is never closed because the symbol is wanted for as long as
    /// the app runs.
    private static let responsibleProcess: ((pid_t) -> pid_t)? = {
        typealias Lookup = @convention(c) (pid_t) -> pid_t
        guard let image = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(image, "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        let lookup = unsafeBitCast(symbol, to: Lookup.self)
        return { lookup($0) }
    }()

    /// The application a process belongs to: itself when it is one, and the app
    /// it was started for when it is a piece of one.
    ///
    /// The responsible process is consulted ONLY for something that is not an
    /// application, and that restraint is the point. An app started from a
    /// terminal can report that terminal as responsible for it, so asking this
    /// about a real app would be a fresh way to name the wrong thing — trading
    /// a helper's name for a shell's.
    private static func owningApplication(of app: NSRunningApplication) -> NSRunningApplication? {
        if isApplication(app) { return app }
        guard let responsibleProcess else { return nil }
        let owner = responsibleProcess(app.processIdentifier)
        guard owner > 0,
              owner != app.processIdentifier,
              let application = NSRunningApplication(processIdentifier: owner),
              isApplication(application)
        else { return nil }
        return application
    }

    /// One entry per application, in the order they were found.
    ///
    /// Resolving helpers to their apps makes duplicates the normal case rather
    /// than a rarity: a browser in a meeting holds the input in more than one
    /// process, and every one of them resolves to the browser. Kept apart from
    /// the live lookup so the rule can be checked on listeners that are built
    /// rather than staged.
    package static func distinct(_ listeners: [Listener]) -> [Listener] {
        var result: [Listener] = []
        for listener in listeners
        where !result.contains(where: { $0.processID == listener.processID }) {
            result.append(listener)
        }
        return result
    }

    /// One microphone holder, named as the application it belongs to, or
    /// nothing when it belongs to no application this can find.
    ///
    /// Package-visible so the checks can state the promise directly: whatever
    /// this returns is an app, never a piece of one.
    package static func attributed(_ listener: Listener) -> Listener? {
        guard let process = NSRunningApplication(processIdentifier: listener.processID),
              let owner = owningApplication(of: process),
              let bundle = owner.bundleIdentifier,
              !bundle.isEmpty,
              let name = owner.localizedName
        else { return nil }
        return Listener(
            bundleIdentifier: bundle,
            name: name,
            processID: owner.processIdentifier
        )
    }

    /// Every real app with an input stream open. Package-visible so the checks
    /// can see it returns nothing surprising on a machine with no call running.
    package static func allListeners() -> [Listener] {
        var size: UInt32 = 0
        var address = processListAddress
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects.compactMap(listener(for:))
    }

    private static func listener(for object: AudioObjectID) -> Listener? {
        guard isRunningInput(object), let pid = processID(of: object) else { return nil }
        // A real application, with a bundle identifier and a name. This is what
        // excludes corespeechd and its kind — a system service holding the
        // microphone open is not somebody being on a call, and treating it as
        // one would light the notch permanently on an ordinary Mac.
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundle = app.bundleIdentifier,
              !bundle.isEmpty,
              let name = app.localizedName
        else { return nil }
        return Listener(bundleIdentifier: bundle, name: name, processID: pid)
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyIsRunningInput),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func processID(of object: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }

    /// The fallback for macOS below 14.4: is *anything* using the default input?
    ///
    /// Device-wide, so it cannot name the app — and it counts the system's own
    /// dictation service, which is why it is only ever consulted when the
    /// per-process list is unavailable.
    package static func inputBusyDeviceWide() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device
        ) == noErr else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &runningSize, &running
        ) == noErr else { return false }
        return running != 0
    }

    /// How long a call has been running, as the notch says it.
    ///
    /// Counts from when the microphone was first seen open, which is not
    /// necessarily when the call was answered — nothing available here knows
    /// that. Minutes and seconds up to an hour, then hours.
    package static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 3_600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}
