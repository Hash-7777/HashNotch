import AppKit
import SwiftUI

/// Visual tokens shared across the HUD and all features, so everything reads as
/// one system. Features should pull colors from here rather than hard-coding.
public struct Theme {
    public var upColor: Color
    public var downColor: Color
    public var textColor: Color
    public var subtitleColor: Color
    public var pillBackground: Color
    public var accent: Color
    public var cornerRadius: CGFloat

    public init(
        upColor: Color,
        downColor: Color,
        textColor: Color,
        subtitleColor: Color,
        pillBackground: Color,
        accent: Color,
        cornerRadius: CGFloat
    ) {
        self.upColor = upColor
        self.downColor = downColor
        self.textColor = textColor
        self.subtitleColor = subtitleColor
        self.pillBackground = pillBackground
        self.accent = accent
        self.cornerRadius = cornerRadius
    }

    /// What to draw ON TOP of anything filled with the accent. White is one of
    /// the accents offered, so a filled control cannot assume a white label.
    public var onAccent: Color {
        let c = NSColor(accent).usingColorSpace(.sRGB) ?? .white
        let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luma > 0.62 ? Color.black.opacity(0.88) : .white
    }

    /// The same theme in a different accent. Everything that tints — icons,
    /// bars, highlights — reads `accent`, so changing it here changes every
    /// feature at once without a single feature knowing a setting exists.
    public func tinted(_ accent: Color) -> Theme {
        var copy = self
        copy.accent = accent
        return copy
    }

    public static let `default` = Theme(
        upColor: Color(red: 0.94, green: 0.30, blue: 0.36),
        downColor: Color(red: 0.30, green: 0.85, blue: 0.46),
        textColor: .white,
        subtitleColor: Color.white.opacity(0.55),
        pillBackground: Color.black.opacity(0.55),
        accent: Color(red: 0.25, green: 0.55, blue: 1.0),
        cornerRadius: 14
    )
}
