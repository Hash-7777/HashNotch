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

    /// The colour a climbing reading takes once it is worth noticing, and the
    /// one it takes when it is the reason you opened the panel.
    ///
    /// Fixed rather than derived from the accent, because a warning that
    /// changes with taste is not a warning. They are also deliberately far from
    /// every accent in the palette, which is the part that was wrong: the
    /// caution colour used to be SwiftUI's `.orange`, and the palette's own
    /// orange — the DEFAULT accent — sits 6.7 ΔE from it. Two colours that
    /// close are one colour on a four-point bar seen at a glance, so on a
    /// default install a disk at 74% and a disk at 76% looked identical and the
    /// whole "quiet until it matters" idea did nothing at all. It also read as
    /// a broken setting: somebody who picked Blue and still saw an orange bar
    /// had no way to know the bar had left the accent on purpose.
    ///
    /// Measured against the six accents: this amber is at least 35 ΔE from
    /// every one of them, and 87 from `danger`. `danger` is the same red the
    /// upload arrow uses, unchanged, and is at least 28 away — its nearest is
    /// the pink accent.
    public static let caution = Color(red: 0.99, green: 0.85, blue: 0.24)
    public static let danger = Color(red: 0.94, green: 0.30, blue: 0.36)

    /// What to fill a reading with at a given level.
    ///
    /// Only for readouts that sit in the accent while nothing is wrong — the
    /// processor, memory, and the disk. The temperature and battery readouts
    /// have their own complete scales, green through yellow and orange to red,
    /// and never wear the accent at all: this amber sits where their yellow
    /// does, so handing them these tokens would merge two of their four bands
    /// and lose a step. They are not an oversight.
    public func color(for level: ReadingLevel) -> Color {
        switch level {
        case .normal: return accent
        case .caution: return Self.caution
        case .danger: return Self.danger
        }
    }

    /// How far apart two colours look, as CIE76 ΔE over CIE Lab.
    ///
    /// Here so the rule above can be checked rather than asserted. Plain
    /// component distance would not do: it calls the palette's orange and the
    /// old caution orange far apart on the blue channel while the eye sees one
    /// colour.
    package static func perceptualDistance(_ first: Color, _ second: Color) -> Double {
        func lab(_ color: Color) -> (Double, Double, Double) {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
            func linear(_ v: Double) -> Double {
                v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let r = linear(Double(c.redComponent))
            let g = linear(Double(c.greenComponent))
            let b = linear(Double(c.blueComponent))
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double {
                t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
            }
            let fx = f(x), fy = f(y), fz = f(z)
            return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
        }
        let (l1, a1, b1) = lab(first)
        let (l2, a2, b2) = lab(second)
        return ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)).squareRoot()
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

/// How far up a climbing reading is: itself while nothing is wrong, then
/// noticeable, then the reason you opened the panel.
///
/// One rule in one place. It was the same three-case switch copied into the
/// processor, memory and disk readouts, each with its own hard-coded orange —
/// which is the thing `Theme` exists to prevent — and the copies had already
/// drifted apart: memory's said it used "the same thresholds as the processor"
/// while using 0.75 and 0.9 against the processor's 0.6 and 0.85.
///
/// The thresholds stay with each readout, because they genuinely differ and
/// should: a processor at 60% is worth a glance, a disk at 60% is simply a
/// disk. Only the colours are shared.
public enum ReadingLevel: Equatable, Sendable {
    case normal
    case caution
    case danger

    /// Which level a reading is at, in whatever unit the reading itself uses —
    /// a fraction for the processor, a percentage for the disk.
    public static func of(_ value: Double, caution: Double, danger: Double) -> ReadingLevel {
        if value >= danger { return .danger }
        if value >= caution { return .caution }
        return .normal
    }
}
