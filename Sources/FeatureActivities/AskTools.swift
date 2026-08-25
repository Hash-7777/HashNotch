import Foundation

/// Which tools stop and ask you on the notch instead of in their own window.
///
/// The list lives in a plain text file, one name per line, because the thing
/// that reads it is a shell script running inside somebody else's agent and a
/// line of text is the one format that cannot go wrong there. What was wrong
/// was that writing that file was also the only way to turn the feature on — so
/// a feature that exists for anybody running an agent was reachable only by
/// people comfortable creating a dotfile by hand.
///
/// The file stays. The app writes it now.
public enum AskTools {
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hashnotch/ask-tools.txt")
    }

    /// The tools worth offering, and what each one means in words rather than
    /// in the name a program knows it by.
    ///
    /// Four, not everything an agent can do. A list of every tool would be a
    /// list nobody reads, and being asked about all of them is the same as
    /// being asked about none — it is the ones that change your machine or
    /// reach outside it that are worth stopping for.
    public static let offered: [(name: String, detail: String)] = [
        ("Bash", "Commands run on your Mac"),
        ("Write", "Creating a file"),
        ("Edit", "Changing a file"),
        ("WebFetch", "Fetching a page from the web"),
    ]

    /// The names in a file's contents.
    ///
    /// Blank lines and anything after a `#` are skipped, so the file can carry
    /// a line explaining itself to whoever opens it. Names are kept exactly as
    /// written, because the script that reads them matches them exactly and a
    /// name this app has tidied is a name that silently stops matching.
    public static func parse(_ contents: String) -> [String] {
        contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// What to write for a given set of names.
    ///
    /// The header is for the person who opens this file wondering what wrote
    /// it. It costs two lines and answers the question the file otherwise
    /// raises.
    public static func text(for names: [String]) -> String {
        let header = """
        # Tools that stop and ask you on the notch instead of in their own window.
        # Written by HashNotch — Settings, Agents. One name per line.
        """
        return ([header] + names).joined(separator: "\n") + "\n"
    }

    /// The names currently on file, or none if there is no file.
    public static func read() -> [String] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return parse(contents)
    }

    /// Turn one tool on or off, leaving every other line alone.
    ///
    /// Names this app does not offer are kept. Somebody may have added a tool
    /// of their own, and a switch here must not quietly delete it.
    public static func setting(_ name: String, on: Bool, in existing: [String]) -> [String] {
        var names = existing.filter { $0 != name }
        if on { names.append(name) }
        return names
    }

    /// Write the list, creating the folder if this is the first time.
    @discardableResult
    public static func write(_ names: [String]) -> Bool {
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // An empty list removes the file rather than leaving an empty one. The
        // script treats "no file" as "intercept nothing", and two ways of
        // saying the same thing is one more than is needed.
        if names.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }
        return (try? text(for: names).write(to: fileURL, atomically: true, encoding: .utf8)) != nil
    }
}
