import Foundation

/// One live activity posted to Hash D Island by another app, a script, or a
/// Shortcut. This is the macOS-honest version of iPhone Live Activities: since
/// no system API lets us read another app's activity, apps push to a local feed
/// and Hash D Island renders it.
public struct LiveActivity: Identifiable, Equatable {
    public let id: String
    public let icon: String        // SF Symbol name, e.g. "bicycle"
    public let title: String
    public let subtitle: String?
    public let progress: Double?   // 0...1, optional bar
    public let endsAt: Date?       // optional countdown target
    /// How long to show this for, counted from the moment it first appears.
    ///
    /// Set this instead of `endsAt` for something that has already happened —
    /// a job that finished, a file that arrived. Those are announcements, not
    /// countdowns: no timer is drawn, and the notice leaves on its own. A
    /// number counting down next to "finished" only ever asked the reader to
    /// watch something that was already over.
    public let dismissAfter: TimeInterval?

    /// An image file to show instead of the SF Symbol — a tool's own logo.
    ///
    /// A symbol cannot be somebody's brand, so a poster that has a mark of its
    /// own points at it here and the notch shows that instead. `icon` stays
    /// required and is used whenever the file is missing or unreadable, so an
    /// activity always has something to draw.
    public let imagePath: String?

    /// An app to bring forward when this activity is clicked in the panel.
    ///
    /// What turns "Claude needs you" from a notification into something you can
    /// act on: the poster names the window that is waiting, and one click goes
    /// there instead of hunting through Spaces for the right terminal. Nil when
    /// the poster named nothing, or named something that is not an app.
    public let appPath: String?

    public init(
        id: String,
        icon: String,
        title: String,
        subtitle: String?,
        progress: Double?,
        endsAt: Date?,
        dismissAfter: TimeInterval?,
        imagePath: String? = nil,
        appPath: String? = nil
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.endsAt = endsAt
        self.dismissAfter = dismissAfter
        self.imagePath = imagePath
        self.appPath = appPath
    }

    /// True when this counts down to something, rather than announcing
    /// something that already happened. Only a countdown draws a timer.
    public var showsCountdown: Bool { endsAt != nil && dismissAfter == nil }

    /// True when this announces something that is already over — a job that
    /// finished, a file that arrived — rather than asking for anything.
    public var isNotice: Bool { dismissAfter != nil }

    /// The subtitle worth drawing, which for a notice is none.
    ///
    /// "HashCortX finished" is the whole message. What the poster tends to put
    /// underneath it is which model answered, or which folder it ran in, and on
    /// a glance surface that is debris: the thing being reported is over, so a
    /// second line adds nothing to act on and costs the first line the room to
    /// be read cleanly. The name of the tool is what the eye is looking for.
    ///
    /// A standing request keeps its subtitle, because there the text IS the
    /// reason it is asking — "Claude needs you" without the reason is a
    /// notification that has withheld the only part worth reading.
    ///
    /// Judged here rather than trusted from the feed, so it holds for every
    /// poster: the app's own Claude Code hook already sends no subtitle on a
    /// finish, but nothing could make that true of anyone else's.
    public var displaySubtitle: String? { isNotice ? nil : subtitle }

    /// Seconds remaining until `endsAt`, if this is a countdown.
    public func secondsLeft(now: Date) -> Int? {
        guard showsCountdown, let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now)))
    }

    public var isExpired: Bool {
        guard let endsAt else { return false }
        return endsAt.timeIntervalSinceNow < -2
    }

    /// When a self-dismissing notice should disappear, given the moment it was
    /// first seen. Nil for everything else.
    ///
    /// `preferred` is the reader's own choice of how long a notice should stay.
    /// It wins over the poster's suggestion: whoever wrote the feed knows what
    /// happened, but only the person looking at the notch knows how long they
    /// want it there.
    public func dismissalDate(firstSeen: Date, preferring preferred: TimeInterval? = nil) -> Date? {
        guard dismissAfter != nil else { return nil }
        return firstSeen.addingTimeInterval(preferred ?? dismissAfter ?? 0)
    }
}

/// Reads the activity feed file. Missing/empty/invalid file → no activities.
///
/// Feed: `~/.hashdisland/activities.json`, an array of objects:
///   {"id","icon","title","subtitle"?,"progress"?,"endsAt"? (ISO8601),
///    "dismissAfter"? (seconds), "image"? (path to a logo)}
///
/// The feed is written by other processes, so everything is bounded before it
/// reaches the UI: the file itself, the number of activities, text lengths,
/// and the progress range. Duplicate ids keep their first occurrence (SwiftUI
/// list identity requires unique ids).
package enum ActivitiesReader {
    /// A feed is a handful of small objects; refuse anything absurdly larger.
    package static let maxFeedBytes = 262_144
    /// The notch is a glanceable surface, not a task manager.
    package static let maxActivities = 8
    private static let maxTextLength = 200
    /// SF Symbol names are short; an unknown name simply draws nothing, but the
    /// length is bounded like every other field so no string from the feed
    /// reaches the UI unmeasured.
    private static let maxIconLength = 64

    static var feedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hashdisland/activities.json")
    }

    /// A notice is glanceable, so its lifetime is clamped rather than trusted:
    /// long enough to read, never long enough to sit on the notch.
    private static let minDismissAfter: TimeInterval = 1
    private static let maxDismissAfter: TimeInterval = 30

    private struct ActivityDTO: Decodable {
        let id: String
        let icon: String?
        let title: String
        let subtitle: String?
        let progress: Double?
        let endsAt: String?
        let dismissAfter: Double?
        let image: String?
        let app: String?
    }

    static func read() -> [LiveActivity] {
        read(from: feedURL)
    }

    package static func read(
        from url: URL,
        appRoots: [String] = standardAppRoots
    ) -> [LiveActivity] {
        guard let data = try? Data(contentsOf: url),
              data.count <= maxFeedBytes,
              let items = try? JSONDecoder().decode([ActivityDTO].self, from: data) else {
            return []
        }

        var seen = Set<String>()
        var result: [LiveActivity] = []
        for dto in items {
            guard result.count < maxActivities else { break }
            let id = String(dto.id.prefix(maxTextLength))
            let title = String(dto.title.prefix(maxTextLength))
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }

            // A missing OR empty icon falls back to the generic badge, so an
            // activity always has something to draw.
            let icon = dto.icon.map { String($0.prefix(maxIconLength)) } ?? ""

            let activity = LiveActivity(
                id: id,
                icon: icon.isEmpty ? "app.badge" : icon,
                title: title,
                subtitle: dto.subtitle.map { String($0.prefix(maxTextLength)) },
                progress: dto.progress.map { min(max($0, 0), 1) },
                endsAt: dto.endsAt.flatMap(parseDate),
                dismissAfter: dto.dismissAfter.map {
                    min(max($0, minDismissAfter), maxDismissAfter)
                },
                imagePath: dto.image.flatMap(safeImagePath),
                appPath: dto.app.flatMap { safeAppPath($0, roots: appRoots) }
            )
            if !activity.isExpired { result.append(activity) }
        }
        return result
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// An image path the app is willing to load.
    ///
    /// The feed is written by other processes, so this is treated like every
    /// other field in it. Only a readable regular file with a known image
    /// extension is accepted, and the path is resolved before it is judged, so
    /// a trail of `..` cannot be used to point the notch at something that only
    /// looks like an image.
    private static let allowedImageTypes: Set<String> = ["png", "jpg", "jpeg", "tiff", "pdf", "heic"]

    /// The largest logo file the notch will open.
    ///
    /// A mark drawn at 21 points is a few kilobytes; this is generous by orders
    /// of magnitude and exists only as a ceiling. Size is bounded here rather
    /// than at the drawing site because decoding happens on the main thread —
    /// an unbounded file named by a feed anyone can write is the one field in
    /// it that could cost the island its smoothness rather than just look wrong.
    package static let maxImageBytes = 4_000_000

    private static func safeImagePath(_ raw: String) -> String? {
        let trimmed = String(raw.prefix(1024))
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL
        guard allowedImageTypes.contains(resolved.pathExtension.lowercased()) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: resolved.path)
        else { return nil }

        let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let size, size > 0, size <= maxImageBytes else { return nil }
        return resolved.path
    }

    /// The only folders an activity may name an app inside.
    ///
    /// Where macOS itself keeps applications, and nowhere else.
    ///
    /// The cryptex entry is not optional padding: on current macOS,
    /// `/Applications/Safari.app` is a symlink into Apple's signed, read-only
    /// cryptex volume. Since paths are resolved before they are judged (so a
    /// link cannot point out of an allowed folder), leaving that entry out
    /// would refuse Safari — a real app, in the folder everyone believes it is
    /// in. The volume it resolves to is sealed by macOS, so it is if anything a
    /// stronger place to trust than `/Applications` itself.
    package static var standardAppRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
            home + "/Applications",
        ]
    }

    /// An app path the panel is willing to open.
    ///
    /// Clicking a row hands the named bundle to `NSWorkspace`, which brings it
    /// forward if it is already open and **starts it if it is not**. That is a
    /// launch, so the field is treated as the capability it is rather than as a
    /// hint, and it is narrowed on three axes at once:
    ///
    ///   * It must be a real `.app` bundle — never a loose executable, and no
    ///     argument or document can be passed with it.
    ///   * It must sit inside one of `standardAppRoots`. The feed is writable by
    ///     anything running as you, so without this a dropped `/tmp/Update.app`
    ///     could wear the words "your build finished" and be opened by a click
    ///     the reader believed was a way back to their own window. Every app
    ///     somebody would genuinely want to return to already lives in these
    ///     folders.
    ///   * Symlinks are resolved before any of that is judged, so a link cannot
    ///     stand inside an allowed folder while pointing at a bundle outside it.
    ///
    /// And it is still only ever acted on when the user clicks the row.
    private static func safeAppPath(_ raw: String, roots: [String]) -> String? {
        let trimmed = String(raw.prefix(1024))
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        // `standardizedFileURL` only collapses `..` as text; a symlink still
        // has to be followed before the path can be judged on where it lands.
        let resolved = URL(fileURLWithPath: expanded)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolved.pathExtension.lowercased() == "app" else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        // Compare on path components, not on text: a prefix match would let
        // "/Applications-mine/Evil.app" pass for being inside "/Applications".
        let parts = resolved.standardizedFileURL.pathComponents
        let allowed = roots.contains { root in
            let rootParts = URL(fileURLWithPath: root)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .pathComponents
            return parts.count > rootParts.count && Array(parts.prefix(rootParts.count)) == rootParts
        }
        guard allowed else { return nil }

        return resolved.path
    }

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterFractional.date(from: string)
    }
}
