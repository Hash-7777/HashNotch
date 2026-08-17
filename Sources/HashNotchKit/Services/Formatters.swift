import Foundation

/// Shared, allocation-light formatters so numbers read consistently everywhere.
public enum Formatters {
    /// Formats a bytes-per-second rate like "9 KB", "2 MB" (unit split out so the
    /// UI can style value and unit differently, matching the reference HUD).
    public static func rate(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let units = ["B", "KB", "MB", "GB"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        // One decimal for small scaled values (2.3 MB/s reads better than 2),
        // but drop a trailing ".0" so 9.0 KB shows as a clean "9".
        let rounded: String
        if value < 10, index > 0 {
            let oneDecimal = (value * 10).rounded() / 10
            rounded = oneDecimal == oneDecimal.rounded()
                ? String(format: "%.0f", oneDecimal)
                : String(format: "%.1f", oneDecimal)
        } else {
            rounded = String(format: "%.0f", value)
        }
        return (rounded, units[index] + "/s")
    }

    /// Unit label paired with `megabytesPerSecond` — always MB/s.
    public static let megabytesUnit = "MB/s"

    /// Formats a bytes-per-second rate as a fixed MB/s value with two decimals,
    /// e.g. 0.01, 12.34. Always MB/s so the readout never changes units and the
    /// layout can reserve a stable width.
    public static func megabytesPerSecond(_ bytesPerSecond: Double) -> String {
        String(format: "%.2f", max(0, bytesPerSecond) / 1_048_576)
    }

    /// A duration in minutes as explicit hours/minutes — "45m", "2h 34m",
    /// "3h" — so a battery estimate never reads like an ambiguous clock time.
    public static func hoursMinutes(_ totalMinutes: Int) -> String {
        let minutes = max(0, totalMinutes)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    /// Compact count for large token totals, e.g. 812, 12.3K, 4.5M, 1.28B.
    public static func compactCount(_ count: Int64) -> String {
        let value = Double(max(0, count))
        switch count {
        case ..<1_000: return "\(max(0, count))"
        case ..<1_000_000: return trimmed(value / 1_000) + "K"
        case ..<1_000_000_000: return trimmed(value / 1_000_000) + "M"
        default: return trimmed(value / 1_000_000_000, decimals: 2) + "B"
        }
    }

    /// A size on disk, in the units macOS itself uses.
    ///
    /// Powers of a thousand, not 1024. Apple switched to decimal units years
    /// ago, and a readout that disagrees with Finder about how much room is
    /// left is worse than no readout — the whole point of it is recognising the
    /// number you already know.
    public static func bytes(_ count: Int64) -> String {
        let value = Double(max(0, count))
        switch count {
        case ..<1_000: return "\(max(0, count)) B"
        case ..<1_000_000: return trimmed(value / 1_000) + " KB"
        case ..<1_000_000_000: return trimmed(value / 1_000_000) + " MB"
        case ..<1_000_000_000_000: return trimmed(value / 1_000_000_000, decimals: 2) + " GB"
        default: return trimmed(value / 1_000_000_000_000, decimals: 2) + " TB"
        }
    }

    private static func trimmed(_ value: Double, decimals: Int = 1) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        return rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.\(decimals)f", rounded)
    }
}
