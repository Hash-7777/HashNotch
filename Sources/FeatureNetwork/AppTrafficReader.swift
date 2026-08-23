import Foundation

/// Asks macOS how much each of your own processes has sent and received.
///
/// `/usr/bin/nettop` is Apple's own tool and the same one Activity Monitor's
/// Network tab is built on. It needs no permission and no private interface,
/// and without root it reports only processes running as you — which is the
/// only set this app has any business showing.
///
/// Run out of process, like the AirPods and Now Playing readers, so it can
/// never wedge the app, and killed if it ever hangs. One sample costs about
/// thirty milliseconds and is taken once a minute alongside the reading the
/// totals already take.
///
/// What comes back is a counter per process, since that process started —
/// exactly the shape the interface counters have, and turned into a daily
/// record the same way.
package enum AppTrafficReader {
    private static let nettop = "/usr/bin/nettop"
    /// One sample is ~30ms measured; kill the read if it ever hangs.
    private static let timeout: TimeInterval = 5

    /// Reads one sample. Returns nil when the tool is unavailable or says
    /// nothing usable, which the caller treats as "no breakdown this minute"
    /// rather than as zero.
    package static func read() -> [String: ProcessBytes]? {
        guard FileManager.default.isExecutableFile(atPath: nettop) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nettop)
        // -P   totals per process rather than per connection: no address, no
        //      port and no remote host is asked for or returned.
        // -L 1 one sample, in the machine-readable logging form, then exit.
        // -J   only these two columns.
        // -t   physical links only. The same exclusion the totals make, and for
        //      the same reason: traffic through a VPN or a bridge also travels
        //      the real link underneath, and counting both reports it twice.
        process.arguments = [
            "-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out", "-t", "wifi", "-t", "wired",
        ]
        process.qualityOfService = .utility
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let reading = parse(output, at: Date())
        return reading.isEmpty ? nil : reading
    }

    /// Parses `nettop -L` output.
    ///
    /// Each line is `<program>.<pid>,<bytes in>,<bytes out>,` and the first is
    /// a header whose first field is empty. Package-visible so the checks can
    /// pin the parsing against captured output rather than against whatever
    /// this machine happens to be running.
    ///
    /// Anything that does not have all three fields, or whose counters are not
    /// numbers, is skipped rather than guessed at — this is a subprocess's
    /// stdout, so it is read with the same suspicion as the activity feed.
    package static func parse(_ output: String, at now: Date) -> [String: ProcessBytes] {
        var result: [String: ProcessBytes] = [:]
        for line in output.components(separatedBy: .newlines) {
            let fields = line.components(separatedBy: ",")
            guard fields.count >= 3 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty,
                  NetworkAppUsageMath.programName(fromKey: key) != nil,
                  let received = UInt64(fields[1].trimmingCharacters(in: .whitespaces)),
                  let sent = UInt64(fields[2].trimmingCharacters(in: .whitespaces))
            else { continue }
            // A pid can appear more than once across interface types; the
            // biggest reading wins rather than the last, since these are
            // counters and a smaller one is a partial view of the same process.
            if let existing = result[key], existing.received >= received, existing.sent >= sent {
                continue
            }
            result[key] = ProcessBytes(received: received, sent: sent, seenAt: now)
        }
        return result
    }
}
