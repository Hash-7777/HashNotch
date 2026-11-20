import Foundation

public extension MenuBarReading {
    /// A figure that is a share of a whole — processor, graphics, memory.
    /// High at the same point the panel turns the same figure red.
    static func share(_ share: Double, title: String) -> MenuBarReading {
        let text = MenuBarText.percent(share)
        return MenuBarReading(
            text: text,
            spoken: "\(title) \(text)",
            isHigh: ReadingLevel.of(share: share) == .danger
        )
    }

    /// A temperature, high at the point the feature names.
    static func temperature(_ celsius: Double, title: String, dangerAt threshold: Double) -> MenuBarReading {
        let text = MenuBarText.degrees(celsius)
        return MenuBarReading(
            text: text,
            spoken: "\(title) \(text)",
            isHigh: ReadingLevel.of(celsius, dangerAt: threshold) == .danger
        )
    }
}
