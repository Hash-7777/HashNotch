import Foundation

/// One music service the app is willing to fetch a cover from, and the hosts
/// that serve it.
///
/// A service rather than a bare list of hosts, because each one is switchable
/// on its own. "This app may talk to Spotify's image servers" and "this app may
/// talk to YouTube's" are different permissions, to different companies, and
/// rolling them into a single on/off would mean somebody who wants covers for
/// the one service they use has to accept requests to another they do not.
///
/// It lives in the core rather than beside the media reader because the
/// settings window has to list these, and the core cannot depend on a feature.
///
/// Apple Music is deliberately absent. Its artwork comes out of the app on this
/// Mac, already decoded, and never touches the network — there is no host to
/// permit and so nothing to ask about.
public struct ArtworkService: Identifiable, Equatable, Sendable {
    public let id: String
    /// What it is called in the settings window.
    public let name: String
    /// Host suffixes this service's pictures may come from.
    public let hosts: [String]
    /// Shown under the switch, so the permission is legible before it is given.
    public let detail: String

    public init(id: String, name: String, hosts: [String], detail: String) {
        self.id = id
        self.name = name
        self.hosts = hosts
        self.detail = detail
    }

    public static let spotify = ArtworkService(
        id: "spotify",
        name: "Spotify",
        hosts: ["scdn.co", "spotifycdn.com"],
        detail: "Album covers, from Spotify's own image servers."
    )
    public static let youtube = ArtworkService(
        id: "youtube",
        name: "YouTube",
        hosts: ["ytimg.com"],
        detail: "Thumbnails for a video playing in your browser."
    )
    /// Every service, in the order the settings window lists them.
    ///
    /// Anghami was here and has been removed, which is worth recording so it is
    /// not attempted again the same way. Its covers ARE reachable: macOS
    /// publishes an artwork identifier beside the image it withholds, and
    /// Anghami's CDN answers to it. But that identifier does not keep step with
    /// the track — it goes stale across a change and is sometimes missing
    /// entirely — so what it produced was often the previous song's cover,
    /// shown with total confidence. A blank tile is honest; a confident wrong
    /// answer about what you are listening to is not, and no amount of
    /// coverage is worth being wrong in the place people look first.
    public static let all: [ArtworkService] = [.spotify, .youtube]

    /// Where this service's on/off switch is stored.
    public var settingKey: String { "artwork.\(id)" }
}

/// Decides which artwork URLs the app is willing to download.
///
/// A cover is the app's ONLY network access, so the rule is deliberately narrow
/// and pinned by the checks: HTTPS only, a host one of the services above owns,
/// and that service switched on. A `file://` or `http://` address is refused
/// outright, and so is a host nobody claims.
///
/// The same rule judges redirects. A trusted CDN that answered with a 302 to
/// somewhere else would otherwise walk the fetch straight off the allowlist,
/// which is the whole point of having one.
public enum ArtworkPolicy {
    /// Which services may be fetched from right now.
    ///
    /// Held here rather than read from the settings store on demand because
    /// this is consulted from the download delegate, on a URLSession queue,
    /// where main-actor state is not reachable — and because a redirect must be
    /// judged by exactly the rule that admitted the original URL, not by
    /// whatever the setting happens to say a moment later.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var enabledServiceIDs: Set<String> =
        Set(ArtworkService.all.map(\.id))

    public static func setEnabledServices(_ ids: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        enabledServiceIDs = ids
    }

    public static func enabledServices() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return enabledServiceIDs
    }

    /// The service that owns a URL's host, or nil when nobody does.
    public static func service(forURL string: String) -> ArtworkService? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return nil }
        return ArtworkService.all.first { service in
            service.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// Whether this exact URL may be fetched right now.
    public static func isTrustedURL(_ string: String) -> Bool {
        guard let service = service(forURL: string) else { return false }
        return enabledServices().contains(service.id)
    }

    /// Album art is ~100 KB; refuse anything absurdly larger.
    public static let maxArtworkBytes = 5_000_000
}
