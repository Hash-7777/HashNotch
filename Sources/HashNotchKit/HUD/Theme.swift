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

    /// The one colour a reading takes when it is running high.
    ///
    /// Fixed rather than derived from the accent, because a warning that
    /// changes with taste is not a warning. And there is only one of it. An
    /// amber "getting high" step used to sit between the accent and this red,
    /// and a middle step is exactly where a warning gets confused with a
    /// choice: next to the orange and yellow people can pick as their colour,
    /// it read as the accent rather than as the reading climbing. One colour
    /// that means one thing is the only version that cannot be misread.
    ///
    /// `danger` is the same red the upload arrow uses, and is at least 28 ΔE
    /// from every accent in the palette — its nearest is the pink one.
    public static let danger = Color(red: 0.94, green: 0.30, blue: 0.36)

    /// What to fill a reading with at a given level: the accent while nothing
    /// is wrong, red once it is.
    public func color(for level: ReadingLevel) -> Color {
        switch level {
        case .normal: return accent
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

/// Whether a reading is running high.
///
/// One rule, one number, for every readout that has a full scale: at 90% of
/// it, a reading turns red, and below that it wears the accent. The processor,
/// memory and the disk all ask this, so they cannot drift apart the way three
/// hand-copied switches once did. Readouts with no full scale — a temperature,
/// a battery running DOWN — name their own point beside their own code, and
/// still answer with these two levels and nothing between them.
public enum ReadingLevel: Equatable, Sendable {
    case normal
    case danger

    /// Where "high" starts, as a share of the whole.
    public static let dangerShare = 0.9

    /// The level of a reading given as a share of its full scale, 0…1.
    public static func of(share: Double) -> ReadingLevel {
        share >= dangerShare ? .danger : .normal
    }

    /// The level of a reading against a point of its own, for readouts whose
    /// scale has no top — a temperature, say.
    public static func of(_ value: Double, dangerAt threshold: Double) -> ReadingLevel {
        value >= threshold ? .danger : .normal
    }
}
