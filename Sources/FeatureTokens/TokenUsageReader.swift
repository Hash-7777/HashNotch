import Foundation
import HashNotchKit

/// Today's token totals, per source. `claude` / `hashCortx` / `hashCerebrum`
/// count PROCESSED tokens — input + cache-write + output — exactly the number
/// HashMeterAi's day view shows, so the two apps always agree. `cached` is the
/// much larger cache-READ total, kept separate so it never inflates the
/// headline.
public struct TokenTotals: Equatable, Codable {
    public var claude: Int64 = 0
    public var hashCortx: Int64 = 0
    public var hashCerebrum: Int64 = 0
    public var cached: Int64 = 0
    public var companion: [String: Int64]? = nil

    public init() {}

    public var total: Int64 { claude + hashCortx + hashCerebrum + (companion?.values.reduce(0, +) ?? 0) }
}

/// The assistant messages already counted today.
///
/// Claude Code rewrites the same message to its transcript repeatedly while it
/// streams, and continued or branched sessions repeat it across files, so the
/// count is only correct if each message id is counted once. Following a whole
/// day means remembering every id seen — on a working machine, hundreds of
/// thousands of them.
///
/// Held as 64-bit hashes rather than as the strings themselves. Keeping the
/// strings cost 87 MB of resident memory on the developer's Mac, measured, for
/// a set whose only question is "have I seen this one". A hash answers that in
/// eight bytes. Two different ids could in principle collide and cost one
/// message's tokens; at a day's volume that chance is smaller than one in a
/// hundred million, and the failure it would cause is a slightly low number
/// rather than a wrong one.
package struct SeenMessages {
    private var hashes: Set<Int> = []

    package init() {}

    package var count: Int { hashes.count }

    /// Records an id and reports whether it is new.
    package mutating func insert(_ id: String) -> Bool {
        hashes.insert(id.hashValue).inserted
    }

    package func contains(_ id: String) -> Bool {
        hashes.contains(id.hashValue)
    }

    package mutating func removeAll() {
        hashes = []
    }
}

/// Reads real token usage from the local files the AI tools write — the same
/// sources HashMeterAi uses:
///
///   • Claude Code   ~/.claude/projects/**/*.jsonl  (message.usage per line)
///   • HashCortx     ~/.hashcortx/usage.jsonl       (ecosystem contract)
///   • HashCerebrum  app-data usage.jsonl           (ecosystem contract)
///
/// Files are streamed line by line in 1 MB chunks and only files touched today
/// are opened. Call from a background queue — it does file IO and JSON parsing.
///
/// The pure entry points here read a whole file. `TokenUsageScanner` is what the
/// app actually uses: it remembers where each file was left and reads only what
/// has been appended since, which is the difference between a poll costing
/// tens of megabytes and costing nothing.
package enum TokenUsageReader {
    static func readToday() -> TokenTotals {
        TokenUsageScanner(companionFolder: LocalActivityFeed.directory).readToday()
    }

    private struct CompanionCount: Decodable {
        let source: String
        let at: Double
        let input: Int64
        let output: Int64
        let measured: Int64
    }

    package static func companionCounts(in folder: URL, now: Date) -> [String: Int64] {
        let calendar = Calendar.current
        var counts: [String: Int64] = [:]
        for url in LocalActivityFeed.files(in: folder, suffix: ".usage.json", maxBytes: 1024) {
            guard let data = LocalActivityFeed.read(url, maxBytes: 1024),
                  let entry = try? JSONDecoder().decode(CompanionCount.self, from: data),
                  !entry.source.isEmpty, entry.source.count <= 40,
                  entry.source.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "-") }),
                  entry.at.isFinite, entry.at > 0,
                  entry.at <= now.timeIntervalSince1970 + 5,
                  calendar.isDate(Date(timeIntervalSince1970: entry.at), inSameDayAs: now),
                  (1...1_000_000_000).contains(entry.measured),
                  (0...1_000_000_000).contains(entry.input), (0...1_000_000_000).contains(entry.output),
                  counts[entry.source] == nil else { continue }
            counts[entry.source] = entry.input + entry.output
        }
        return counts
    }

    // MARK: Sources

    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var claudeProjectsURL: URL {
        home.appendingPathComponent(".claude/projects")
    }

    static var hashCortxURL: URL {
        home.appendingPathComponent(".hashcortx/usage.jsonl")
    }

    static var hashCerebrumURL: URL {
        home.appendingPathComponent("Library/Application Support/com.hashcerebrum.desktop/usage.jsonl")
    }

    // MARK: What one pass over part of a file produced

    /// What a scan counted, and the offset it finished at.
    ///
    /// `endOffset` is always the position just after the last COMPLETE line —
    /// never inside a partial one. A transcript is appended to while the app is
    /// reading it, so a tail without its newline is a line still being written;
    /// resuming from before it is what lets the next pass see it whole instead
    /// of counting a fragment and then losing the record.
    package struct Scan: Equatable {
        package var io: Int64 = 0
        package var cache: Int64 = 0
        package var endOffset: UInt64 = 0

        package init(io: Int64 = 0, cache: Int64 = 0, endOffset: UInt64 = 0) {
            self.io = io
            self.cache = cache
            self.endOffset = endOffset
        }
    }

    // MARK: Claude Code

    /// Claude Code rewrites the same assistant message to the transcript many
    /// times while it streams (well over half of a day's lines are duplicates),
    /// so summing every line badly overcounts. Matching HashMeterAi: count only
    /// `type == "assistant"` lines and count each `message.id` once. Lines
    /// without an id (rare) are counted — there is nothing to dedup them by.
    package static func scan(
        claudeFile url: URL,
        since: Date,
        from offset: UInt64,
        countsUnterminatedTail: Bool,
        seen: inout SeenMessages
    ) -> Scan {
        var scan = Scan(endOffset: offset)
        let dayPrefix = utcDayPrefix(of: since)
        // `seen` is captured by a non-escaping closure, so it is taken out and
        // put back rather than passed through as an inout capture.
        var localSeen = seen
        scan.endOffset = forEachLine(
            of: url, from: offset, countsUnterminatedTail: countsUnterminatedTail
        ) { line in
            // A byte search before any JSON is built. Most lines in a
            // transcript are not assistant records — user turns, tool results,
            // summaries — and building a dictionary for each of them just to
            // read one field was the bulk of the parsing cost. This is a filter,
            // not the decision: a line that passes is still checked properly
            // below, so a false positive costs a parse and nothing else.
            guard containsAssistantMarker(line) else { return }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  isAtOrAfter(object["timestamp"] as? String, since: since, utcDayPrefix: dayPrefix),
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            if let id = message["id"] as? String, !id.isEmpty {
                guard localSeen.insert(id) else { return }
            }
            scan.io += int(usage["input_tokens"]) + int(usage["output_tokens"])
                + int(usage["cache_creation_input_tokens"])
            scan.cache += int(usage["cache_read_input_tokens"])
        }
        seen = localSeen
        return scan
    }

    /// Reads a whole Claude transcript. Kept as the plain, offsetless form the
    /// checks exercise; the app goes through `TokenUsageScanner`.
    package static func tokens(
        inClaudeFile url: URL,
        since: Date,
        seen: inout SeenMessages
    ) -> (io: Int64, cache: Int64) {
        let scan = scan(
            claudeFile: url, since: since, from: 0,
            countsUnterminatedTail: true, seen: &seen
        )
        return (scan.io, scan.cache)
    }

    // MARK: Ecosystem usage.jsonl

    package static func scan(
        ecosystemFile url: URL,
        since: Date,
        from offset: UInt64,
        countsUnterminatedTail: Bool
    ) -> Scan {
        var scan = Scan(endOffset: offset)
        let dayPrefix = utcDayPrefix(of: since)
        scan.endOffset = forEachLine(
            of: url, from: offset, countsUnterminatedTail: countsUnterminatedTail
        ) { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  isAtOrAfter(object["ts"] as? String, since: since, utcDayPrefix: dayPrefix)
            else { return }
            scan.io += int(object["input_tokens"]) + int(object["output_tokens"])
                + int(object["cache_write"])
            scan.cache += int(object["cache_read"])
        }
        return scan
    }

    package static func tokens(
        inEcosystemFile url: URL,
        since: Date
    ) -> (io: Int64, cache: Int64) {
        let scan = scan(
            ecosystemFile: url, since: since, from: 0, countsUnterminatedTail: true
        )
        return (scan.io, scan.cache)
    }

    // MARK: Line streaming

    /// A single usage record is a few kilobytes at most. Carrying more than
    /// this across chunk boundaries would mean the file has no newline where one
    /// is expected — a corrupt or wildly out-of-contract file — so the oversized
    /// line is dropped rather than grown in memory without limit.
    private static let maxLineBytes = 8 << 20
    private static let chunkBytes = 1 << 20

    /// Calls `body` with each newline-terminated line between `offset` and the
    /// end of the file, and returns the offset just past the last complete line.
    ///
    /// Reads in 1 MB chunks so even a huge transcript never sits in memory
    /// whole. A partial line at a chunk boundary is carried into the next read.
    ///
    /// `countsUnterminatedTail` decides what happens to bytes at the end of the
    /// file with no newline after them. Reading a file whole — which is what the
    /// pure entry points above do — they are the last line of a file that simply
    /// does not end in a newline, and they count. Reading incrementally they are
    /// a line still being written, and counting them would either double-count
    /// the record or, worse, consume it as a fragment and lose it. The returned
    /// offset excludes them either way.
    @discardableResult
    private static func forEachLine(
        of url: URL,
        from offset: UInt64,
        countsUnterminatedTail: Bool,
        _ body: (ArraySlice<UInt8>) -> Void
    ) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        if offset > 0 {
            guard (try? handle.seek(toOffset: offset)) != nil else { return offset }
        }

        var carry: [UInt8] = []
        var totalRead = 0
        // Set while a line has outgrown the cap, so the rest of that line is
        // discarded up to its newline instead of being buffered.
        var skippingLine = false

        while let chunk = try? handle.read(upToCount: chunkBytes), !chunk.isEmpty {
            totalRead += chunk.count

            var buffer: [UInt8]
            if carry.isEmpty {
                buffer = [UInt8](chunk)
            } else {
                buffer = carry
                buffer.append(contentsOf: chunk)
                carry = []
            }

            // One pool per chunk, drained before the next is read.
            //
            // `JSONSerialization` hands back autoreleased Foundation objects,
            // and the pool belonging to a dispatch block is not drained until
            // that block returns. So a full pass over a day's transcripts held
            // every dictionary it had ever built, all at once, until the whole
            // scan finished — 85 MB of resident memory on the developer's Mac,
            // measured, for objects the reader had already finished with. The
            // pool goes around the chunk rather than each line because the cost
            // is in what it holds, not in how often it is drained.
            autoreleasepool {
                var start = 0
                while let newline = newlineIndex(in: buffer, from: start) {
                    if skippingLine {
                        skippingLine = false
                    } else if newline > start {
                        // A slice, not a copy. Handing each line out as its own
                        // array allocated once per line for a corpus of hundreds
                        // of thousands of them, and all but a few were about to
                        // be discarded by the filter without being looked at.
                        body(buffer[start..<newline])
                    }
                    start = newline + 1
                }

                if start < buffer.count {
                    if buffer.count - start > maxLineBytes {
                        skippingLine = true
                    } else {
                        carry = Array(buffer[start...])
                    }
                }
            }
        }

        if countsUnterminatedTail, !carry.isEmpty, !skippingLine {
            body(carry[...])
        }
        // Never past the last newline: whatever is still in `carry` is either a
        // line being written or a file that does not end in one, and both want
        // reading again from where it starts.
        return offset + UInt64(totalRead) - UInt64(carry.count)
    }

    /// The offset of the next newline at or after `start`, via `memchr` — one
    /// libc call running at memory bandwidth.
    ///
    /// This used to be `data[start...].firstIndex(of: 0x0A)`, which walks a
    /// `Data` slice a byte at a time through Foundation's bridging and was, on
    /// its own, the second heaviest thing the whole app did.
    private static func newlineIndex(in buffer: [UInt8], from start: Int) -> Int? {
        guard start < buffer.count else { return nil }
        return buffer.withUnsafeBufferPointer { raw -> Int? in
            guard let base = raw.baseAddress else { return nil }
            let from = base + start
            guard let hit = memchr(from, 0x0A, buffer.count - start) else { return nil }
            return start + UnsafeRawPointer(hit).assumingMemoryBound(to: UInt8.self) - from
        }
    }

    /// The bytes every assistant record contains. Deliberately the bare value
    /// rather than `"type":"assistant"`: the key and value are adjacent in the
    /// files this reads, but a writer that put a space after the colon would
    /// make the stricter pattern silently skip real records, and a filter that
    /// can undercount is worse than one that occasionally lets a line through.
    private static let assistantMarker = Array("assistant".utf8)

    private static func containsAssistantMarker(_ line: ArraySlice<UInt8>) -> Bool {
        contains(line, assistantMarker)
    }

    private static func contains(_ haystack: ArraySlice<UInt8>, _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count, !needle.isEmpty else { return false }
        return haystack.withUnsafeBufferPointer { hay in
            needle.withUnsafeBufferPointer { pin in
                guard let hayBase = hay.baseAddress, let pinBase = pin.baseAddress else {
                    return false
                }
                return memmem(hayBase, hay.count, pinBase, pin.count) != nil
            }
        }
    }

    // MARK: Time

    /// The UTC calendar day `since` falls in, as `yyyy-MM-dd`.
    ///
    /// The timestamps in these files are UTC; the day the app cares about is the
    /// user's local one. Those are different days for part of every 24 hours,
    /// which is exactly why the comparison below is three-way rather than an
    /// equality test on the date part.
    package static func utcDayPrefix(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        // `.gmt` is macOS 13; `TimeZone(secondsFromGMT: 0)` names the same zone
        // and exists everywhere. This is only the fallback's fallback — the
        // identifier lookup answers on every system.
        calendar.timeZone = TimeZone(identifier: "UTC")
            ?? TimeZone(secondsFromGMT: 0)
            ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// Whether an ISO 8601 timestamp is at or after `since`, deciding almost
    /// every line on ten characters instead of by building a `Date`.
    ///
    /// ISO 8601 UTC strings sort chronologically as text, so the date part alone
    /// settles the question except on the one day that straddles the boundary:
    /// a day before `since`'s UTC day is certainly too old, a day after it is
    /// certainly recent enough, and only a timestamp on that same day has to be
    /// parsed properly. `ISO8601DateFormatter` is expensive enough that running
    /// it per line made it the third heaviest thing the app did; this leaves it
    /// handling a sliver of the work while giving exactly the same answers.
    package static func isAtOrAfter(
        _ timestamp: String?,
        since: Date,
        utcDayPrefix dayPrefix: String
    ) -> Bool {
        guard let timestamp, timestamp.count >= 10 else { return false }
        let day = String(timestamp.prefix(10))
        if day < dayPrefix { return false }
        if day > dayPrefix { return true }
        guard let date = parse(timestamp) else { return false }
        return date >= since
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    private static func parse(_ timestamp: String) -> Date? {
        isoFormatter.date(from: timestamp) ?? isoFormatterNoFraction.date(from: timestamp)
    }

    // MARK: Helpers

    static func int(_ value: Any?) -> Int64 {
        if let number = value as? Int64 { return number }
        if let number = value as? Int { return Int64(number) }
        if let number = value as? Double { return Int64(number) }
        return 0
    }
}
