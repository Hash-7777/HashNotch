import Foundation

/// Whether the notch hook installed in your home folder is the one this build
/// of the app ships.
///
/// The hook is deliberately COPIED into `~/.hashnotch` rather than run out of
/// the app bundle, so that anybody can read exactly what is about to run inside
/// their own agent's session before it does. The cost of that is the whole
/// reason this file exists: a copy does not follow the app. Update HashNotch
/// and the hook on disk stays exactly as it was, so a change to what the notch
/// says when a tool finishes — or a fix to how it asks for permission — simply
/// never arrives, and nothing anywhere says why.
///
/// It has already happened. The mark shown when Claude finishes was changed
/// from stars to a tick, the app was rebuilt, and the notch went on drawing
/// stars, because the hook that draws it was three days old and nothing was
/// watching. The installer notices — it compares what it is about to write with
/// what is there — but only once somebody has decided to run it, which is
/// exactly the decision they cannot make while nothing has told them.
public enum HookState: Equatable, Sendable {
    /// Nothing can be said. Running unbundled, or a version that will not parse.
    /// Silence is the only honest answer, and the notice stays away.
    case unknown
    /// No hook is installed, so there is nothing to be out of date. Not a
    /// problem and never reported as one — most people have not installed it.
    case notInstalled
    case current
    case outOfDate(installed: Int, available: Int)

    /// Whether this is worth interrupting somebody about.
    public var needsAttention: Bool {
        if case .outOfDate = self { return true }
        return false
    }
}

/// Reads and compares hook versions.
///
/// Everything that decides anything is pure and takes the two files' contents,
/// so the rules below are pinned by the checks rather than by whatever happens
/// to be installed on the machine running them.
public enum HookInstallation {
    /// The stamp the hook carries: `HOOK_VERSION=9` at the start of a line.
    ///
    /// Only at the start of a line, and only digits, so the sentence in the
    /// hook's own comments that tells you how to read it —
    /// `grep HOOK_VERSION= ~/.hashnotch/claude-code-hook.sh` — is not mistaken
    /// for the stamp itself.
    public static func version(in contents: String) -> Int? {
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("HOOK_VERSION=") else { continue }
            let digits = line.dropFirst("HOOK_VERSION=".count).prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return Int(digits)
        }
        return nil
    }

    /// What to say about the installed hook, given what is installed and what
    /// this build ships.
    ///
    /// The comparison is the VERSION NUMBER and deliberately not the bytes,
    /// which is the opposite of what the installer does — and the difference is
    /// the point. The installer compares bytes because it is about to overwrite
    /// the file and a silent "already current" would stop somebody re-running
    /// it when they should. This is a notice that will sit in somebody's panel,
    /// and the documentation invites people to open the hook and read it. Byte
    /// comparison would nag every person who changed so much as a comment in
    /// their own copy, for ever, with no way to make it stop short of undoing
    /// their edit. A version that has moved on is a claim about this app's
    /// releases rather than about their file.
    ///
    /// It costs the case where the hook changes and its stamp is forgotten —
    /// which has happened once. That is a mistake this repository can catch on
    /// its own way in, and CI does: a push that changes the hook without
    /// changing its version fails. Better there than by pestering the person
    /// who did nothing wrong.
    ///
    /// An installed version AHEAD of the bundled one is `current`, not a
    /// problem: it means an older app and a newer hook, which is somebody
    /// mid-upgrade, and telling them their hook is "out of date" would be
    /// false.
    public static func state(installed: String?, available: String?) -> HookState {
        guard let available, let availableVersion = version(in: available) else { return .unknown }
        guard let installed else { return .notInstalled }
        guard let installedVersion = version(in: installed) else { return .unknown }
        guard installedVersion < availableVersion else { return .current }
        return .outOfDate(installed: installedVersion, available: availableVersion)
    }

    /// The hook this build ships, inside the app bundle.
    ///
    /// Nil when running unbundled — `swift run` has no Resources folder — which
    /// becomes `.unknown` above and says nothing. A developer running from the
    /// source tree is not somebody to warn about a stale copy.
    static func bundledHookURL() -> URL? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("scripts/claude-code-hook.sh")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The hook installed in the home folder, under either name this app has
    /// had. Newest first, matching the feed's own order — a home folder that
    /// has both is one that was installed under the old name and re-installed
    /// under the new one.
    static func installedHookURL(
        in home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        ActivitiesReader.feedFolders
            .map { home.appendingPathComponent("\($0)/claude-code-hook.sh") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Reads both and compares them. Off the main thread — it opens two files.
    static func currentState() -> HookState {
        guard let availableURL = bundledHookURL(),
              let available = try? String(contentsOf: availableURL, encoding: .utf8)
        else { return .unknown }
        let installed = installedHookURL().flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        return state(installed: installed, available: available)
    }

    /// What somebody has to run to fix it.
    ///
    /// The path inside the bundle, because that is the copy that matches the
    /// app they are running, and because somebody who installed the `.app` has
    /// no source tree to run it from. Quoted, since the folder it lives in has
    /// been called things with spaces in before.
    /// Set the hook up, from the app, with no terminal involved.
    ///
    /// It runs the very script the panel used to ask people to copy and paste,
    /// out of the app's own bundle. That script is the thing that has always
    /// done this work; what changes is only who types it.
    ///
    /// Off the main thread, because it writes two files and reads a third, and
    /// the settings window it is called from must not freeze while it does.
    /// The result comes back on the main thread with whatever the script said,
    /// so a failure can be shown rather than swallowed.
    @MainActor
    public static func install(completion: @escaping @MainActor (Bool, String) -> Void) {
        guard let script = installerURL else {
            completion(false, "The installer is missing from this copy of the app.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = script
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(false, message) }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = task.terminationStatus == 0
            Task { @MainActor in completion(ok, output) }
        }
    }

    /// The one line worth showing when the installer refuses.
    ///
    /// Everything the script wrote, out and error together, arrives here. The
    /// panel row that shows it is a single line of eight-point text, so it
    /// cannot be the whole transcript — but it must not be a shrug either, and
    /// for a month it was one. The row said "Could not update it" and dropped
    /// the output on the floor, while the output itself read
    /// `install-claude-hooks.sh: line 225: unexpected EOF while looking for
    /// matching \'` — the entire diagnosis, captured and then discarded. The
    /// script had never once parsed under the bash macOS ships, and the app
    /// knew and would not say.
    ///
    /// The LAST line, because that is where a shell puts the error that stopped
    /// it and where this script puts its own `ERROR:` refusal; earlier lines
    /// are the steps that did succeed. The leading path is stripped because a
    /// row this narrow spent on `/Users/…/Contents/Resources/scripts/` says
    /// nothing, and the file it names is never in doubt.
    public static func failureReason(from output: String) -> String {
        let lastLine = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard var reason = lastLine else {
            return "It did not finish. Nothing was changed."
        }
        // `some/path/install-claude-hooks.sh: line 4: ...` → `line 4: ...`.
        // Only a prefix that ends in a shell script's name, so a message that
        // simply contains a colon keeps all of itself.
        if let colon = reason.firstIndex(of: ":"),
           reason[reason.startIndex..<colon].hasSuffix(".sh") {
            reason = String(reason[reason.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return reason.isEmpty ? "It did not finish. Nothing was changed." : reason
    }

    /// The installer inside this app, or nil when running unbundled.
    public static var installerURL: URL? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/scripts/install-claude-hooks.sh")
    }

    public static var updateCommand: String {
        let path = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Resources/scripts/install-claude-hooks.sh").path
            : "./scripts/install-claude-hooks.sh"
        return "\"\(path)\""
    }
}
