import Foundation

/// Counts today's tokens by reading only what has been appended since the last
/// time it looked.
///
/// The files behind this readout are append-only transcripts, and on a working
/// machine they are large: measured on the developer's Mac, the Claude Code
/// transcripts touched in a single day came to 52 MB. Re-reading all of that
/// from byte zero on every poll — parsing every line to recompute a number that
/// had grown by a few kilobytes — was, by a wide margin, the most expensive
/// thing the whole app did.
///
/// So each file's read position is remembered and the next pass starts there.
/// A poll in the steady state reads whatever was appended since the last one,
/// which is usually nothing at all.
///
/// The remembered positions live only as long as the process. They are
/// deliberately NOT persisted: the set of already-counted message ids goes with
/// them, and resuming from a saved offset without that set would silently
/// under-count every message that streamed across a restart. One full pass per
/// launch is the honest price, and `TokenTotalsCache` means the panel still
/// shows a number immediately while it runs.
///
/// Confined to one serial queue by its owner — see `TokensMonitor`.
package final class TokenUsageScanner: @unchecked Sendable {
    /// Which total a file's numbers land in.
    package enum Bucket: Sendable {
        case claude
        case hashCortx
        case hashCerebrum
    }

    /// Where one file was left, and what it has contributed so far today.
    private struct FileState {
        var bucket: Bucket
        var inode: UInt64
        var offset: UInt64
        var io: Int64
        var cache: Int64
    }

    private let companionFolder: URL?
    private let claudeProjects: URL
    private let ecosystemFiles: [(url: URL, bucket: Bucket)]
    private var files: [String: FileState] = [:]
    /// Shared across ALL files: continued and branched sessions repeat the same
    /// assistant message in more than one transcript.
    private var seen = SeenMessages()
    /// The local day the state above belongs to.
    private var day: Date?

    /// The sources are parameters purely so the checks can point a scanner at a
    /// temporary folder: the behaviour worth pinning here — resuming, rotation,
    /// a day turning over — cannot be produced against the real home directory
    /// on demand.
    package init(
        claudeProjects: URL = TokenUsageReader.claudeProjectsURL,
        ecosystemFiles: [(url: URL, bucket: Bucket)] = [
            (TokenUsageReader.hashCortxURL, .hashCortx),
            (TokenUsageReader.hashCerebrumURL, .hashCerebrum),
        ],
        companionFolder: URL? = nil
    ) {
        self.companionFolder = companionFolder
        self.claudeProjects = claudeProjects
        self.ecosystemFiles = ecosystemFiles
    }

    /// How many full passes this scanner has made. Package-visible so the
    /// checks can prove a second poll over unchanged files does not re-read
    /// them — the entire point of the type, and invisible from the totals.
    package private(set) var fullPasses = 0
    /// Bytes actually read from disk on the most recent call.
    package private(set) var lastBytesRead: UInt64 = 0

    /// Forget everything and count from scratch on the next call.
    package func reset() {
        files = [:]
        seen.removeAll()
        day = nil
    }

    package func readToday(now: Date = Date()) -> TokenTotals {
        let startOfDay = Calendar.current.startOfDay(for: now)
        if day != startOfDay {
            // A new day is a different question, not more of the same one.
            files = [:]
            seen.removeAll()
            day = startOfDay
        }

        var sources = claudeFiles(since: startOfDay)
        for file in ecosystemFiles {
            guard let stamp = Self.stamp(of: file.url.path) else { continue }
            sources.append(Source(
                url: file.url, kind: .ecosystem, bucket: file.bucket,
                inode: stamp.inode, size: stamp.size
            ))
        }

        // A file that shrank, or that is a different file wearing the same name,
        // invalidates more than itself: the already-counted message ids are
        // shared across every transcript, so there is no way to withdraw one
        // file's contribution in isolation. Rotation is rare; starting the day's
        // count again is the answer that cannot be subtly wrong.
        let rotated = sources.contains { source in
            guard let known = files[source.url.path] else { return false }
            return known.inode != source.inode || source.size < known.offset
        }
        if rotated {
            files = [:]
            seen.removeAll()
        }

        var bytes: UInt64 = 0
        var didFullPass = false
        for source in sources {
            let known = files[source.url.path]
            let from = known?.offset ?? 0
            if from == 0 { didFullPass = true }
            // Nothing new: skip the open entirely.
            if let known, source.size == known.offset, known.inode == source.inode { continue }

            let scan: TokenUsageReader.Scan
            switch source.kind {
            case .claude:
                scan = TokenUsageReader.scan(
                    claudeFile: source.url, since: startOfDay, from: from,
                    countsUnterminatedTail: false, seen: &seen
                )
            case .ecosystem:
                scan = TokenUsageReader.scan(
                    ecosystemFile: source.url, since: startOfDay, from: from,
                    countsUnterminatedTail: false
                )
            }

            bytes += scan.endOffset > from ? scan.endOffset - from : 0
            files[source.url.path] = FileState(
                bucket: source.bucket,
                inode: source.inode,
                offset: scan.endOffset,
                io: (known?.io ?? 0) + scan.io,
                cache: (known?.cache ?? 0) + scan.cache
            )
        }

        lastBytesRead = bytes
        if didFullPass {
            fullPasses += 1
            // A full pass reads every transcript the day has produced, and the
            // allocator keeps the pages it needed to do it — resident memory
            // stays at that high-water mark for the rest of the run even though
            // nothing is using it. Handing them back is worth doing for an app
            // whose whole claim is that it sits at the top of the screen costing
            // nothing. It happens once per launch, on a background queue, and
            // only after a pass that actually read a file from the beginning.
            malloc_zone_pressure_relief(nil, 0)
        }
        var result = totals()
        if let folder = companionFolder {
            let counts = TokenUsageReader.companionCounts(in: folder, now: now)
            result.companion = counts.isEmpty ? nil : counts
        }
        return result
    }

    private func totals() -> TokenTotals {
        var result = TokenTotals()
        for state in files.values {
            result.cached += state.cache
            switch state.bucket {
            case .claude: result.claude += state.io
            case .hashCortx: result.hashCortx += state.io
            case .hashCerebrum: result.hashCerebrum += state.io
            }
        }
        return result
    }

    // MARK: Finding the files

    private enum Kind {
        case claude
        case ecosystem
    }

    private struct Source {
        let url: URL
        let kind: Kind
        let bucket: Bucket
        let inode: UInt64
        let size: UInt64
    }

    /// Every Claude transcript touched today, with the one `stat` that answers
    /// how big it is, whether it is still the same file, and when it changed.
    private func claudeFiles(since: Date) -> [Source] {
        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjects,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Source] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let stamp = Self.stamp(of: url.path) else { continue }
            // A file untouched since before today holds nothing today's count
            // wants — unless it is one already being followed, whose remembered
            // position must still be carried forward.
            if stamp.modified < since, files[url.path] == nil { continue }
            found.append(Source(
                url: url, kind: .claude, bucket: .claude,
                inode: stamp.inode, size: stamp.size
            ))
        }
        return found
    }

    /// Inode, size and modification time in a single syscall.
    private static func stamp(of path: String) -> (inode: UInt64, size: UInt64, modified: Date)? {
        // `Darwin.stat` names the struct; the unqualified call resolves to the
        // syscall by its argument types.
        var info = Darwin.stat()
        guard stat(path, &info) == 0 else { return nil }
        return (
            UInt64(info.st_ino),
            UInt64(info.st_size),
            Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        )
    }
}
