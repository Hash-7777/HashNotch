import Foundation

/// AirPods battery, read from `system_profiler SPBluetoothDataType`. Each field
/// is nil when the device doesn't report it — a single-battery model, or no
/// case docked. Everything nil ⇒ nothing connected ⇒ the feature shows nothing.
public struct AirPodsBattery: Equatable {
    public let left: Int?
    public let right: Int?
    public let caseLevel: Int?
    public let single: Int?

    public init(left: Int?, right: Int?, caseLevel: Int?, single: Int?) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.single = single
    }

    public var isEmpty: Bool {
        left == nil && right == nil && caseLevel == nil && single == nil
    }

    /// The number worth a glance: the lower earbud (whichever runs out first),
    /// or the single combined level when that's all the device reports.
    public var glance: Int? {
        [left, right].compactMap { $0 }.min() ?? single
    }
}

/// What the panel's one AirPods row says, in order: each earbud as "L" and "R",
/// the case when it is docked, and a single level with no letter for a model
/// that only reports one.
///
/// One row rather than a heading and a row per part. Three rows of three words
/// each took the height of a paragraph to say three numbers.
package enum AirPodsSummary {
    package struct Item: Equatable {
        package let label: String
        package let percent: Int

        package init(label: String, percent: Int) {
            self.label = label
            self.percent = percent
        }
    }

    package static func items(for battery: AirPodsBattery) -> [Item] {
        var items: [Item] = []
        if let single = battery.single, battery.left == nil, battery.right == nil {
            items.append(Item(label: "", percent: single))
        } else {
            if let left = battery.left { items.append(Item(label: "L", percent: left)) }
            if let right = battery.right { items.append(Item(label: "R", percent: right)) }
        }
        if let caseLevel = battery.caseLevel { items.append(Item(label: "Case", percent: caseLevel)) }
        return items
    }

    /// Where a level turns red: the same 10% the Mac's own battery uses, and
    /// no amber step before it.
    package static let lowPercent = 10

    package static func isLow(_ percent: Int) -> Bool { percent <= lowPercent }
}

/// Reads AirPods battery from macOS. The battery lines only appear while the
/// device is CONNECTED, so a disconnected pair yields an empty result and the
/// feature quietly shows nothing. System-provided data only — no private APIs,
/// and the read runs out of process so it can never wedge the app.
package enum AirPodsReader {
    private static let systemProfiler = "/usr/sbin/system_profiler"
    /// Bluetooth data is quick (~0.3s), but kill the read if it ever hangs.
    private static let timeout: TimeInterval = 5

    /// Run `system_profiler SPBluetoothDataType` and parse the AirPods battery.
    /// Returns nil when nothing is connected (or the tool is unavailable).
    static func read() -> AirPodsBattery? {
        guard FileManager.default.isExecutableFile(atPath: systemProfiler) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: systemProfiler)
        process.arguments = ["SPBluetoothDataType"]
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
        let battery = parse(output)
        return battery.isEmpty ? nil : battery
    }

    /// Parse the AirPods battery from a full `SPBluetoothDataType` dump. Apple's
    /// field names are "Left Battery Level", "Right Battery Level", "Case Battery
    /// Level", or a single "Battery Level" — each "<n>%". Package-visible so the
    /// checks can pin the parsing without a real device.
    package static func parse(_ output: String) -> AirPodsBattery {
        let empty = AirPodsBattery(left: nil, right: nil, caseLevel: nil, single: nil)
        let lines = output.components(separatedBy: .newlines)

        // The AirPods device is a heading line "<name>'s AirPods:".
        guard let start = lines.firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.lowercased().contains("airpod") && trimmed.hasSuffix(":")
        }) else { return empty }

        let headingIndent = leadingSpaces(lines[start])
        var left: Int?, right: Int?, caseLevel: Int?, single: Int?

        for line in lines[lines.index(after: start)...] {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            // The device's block ends where indentation returns to (or above)
            // the heading — i.e. the next device or section.
            if leadingSpaces(line) <= headingIndent { break }
            let lower = line.lowercased()
            guard lower.contains("battery level"), let value = percent(in: line) else { continue }
            if lower.contains("left battery") { left = value }
            else if lower.contains("right battery") { right = value }
            else if lower.contains("case battery") { caseLevel = value }
            else { single = value }
        }
        return AirPodsBattery(left: left, right: right, caseLevel: caseLevel, single: single)
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    /// The integer immediately before a "%" in a "… : 81%" line.
    private static func percent(in line: String) -> Int? {
        guard let end = line.firstIndex(of: "%") else { return nil }
        let digits = line[..<end].reversed().prefix { $0.isNumber }.reversed()
        return Int(String(digits))
    }
}
