import CoreGraphics

/// The pictures the menu bar's panel draws beside each figure's name.
///
/// Solid silhouettes with the detail cut out of them — the core of the chip,
/// the fan of the card, the slots of the memory stick — rather than the panel's
/// outlines, because the panel sits on glass over any wallpaper and a solid
/// shape holds there. They are deliberately NOT drawn in the menu bar itself:
/// at nine points a graphics card or a memory stick has to be guessed at, so
/// the bar carries a word instead (`MenuBarMeter.label`).
///
/// Laid out on the same 100 x 100 grid as the panel's family, and drawn as
/// fills only, so there is no line weight to go wrong.
public enum MenuBarGlyph: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case temperature

    /// The grid every glyph is drawn on.
    public static let grid: CGFloat = 100

    /// One solid piece of a glyph. With `evenOdd`, every path inside another
    /// in the same piece is cut out of it — that is how the detail is drawn.
    public struct Piece {
        public let path: CGPath
        public let evenOdd: Bool
    }

    /// The glyph's pieces, scaled into `box`.
    public func pieces(in box: CGRect) -> [Piece] {
        let scale = min(box.width, box.height) / Self.grid
        var transform = CGAffineTransform(translationX: box.minX, y: box.minY)
            .scaledBy(x: scale, y: scale)
        return unscaled.map { piece in
            Piece(path: piece.path.copy(using: &transform) ?? piece.path, evenOdd: piece.evenOdd)
        }
    }

    private var unscaled: [Piece] {
        switch self {
        case .cpu: return Self.cpuGlyph
        case .gpu: return Self.gpuGlyph
        case .memory: return Self.memoryGlyph
        case .temperature: return Self.temperatureGlyph
        }
    }

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
               cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// A chip: a solid body with its core cut out, and two pins a side.
    private static var cpuGlyph: [Piece] {
        let body = CGMutablePath()
        body.addPath(rounded(20, 20, 60, 60, 12))
        body.addPath(rounded(37, 37, 26, 26, 5))
        let pins = CGMutablePath()
        for offset: CGFloat in [33, 56] {
            pins.addPath(rounded(offset, 4, 11, 20, 3))
            pins.addPath(rounded(offset, 76, 11, 20, 3))
            pins.addPath(rounded(4, offset, 20, 11, 3))
            pins.addPath(rounded(76, offset, 20, 11, 3))
        }
        return [Piece(path: body, evenOdd: true), Piece(path: pins, evenOdd: false)]
    }

    /// A graphics card: a solid board with its fan cut out and the hub left
    /// standing, the bracket it mounts by, and the contacts along its edge.
    private static var gpuGlyph: [Piece] {
        let board = CGMutablePath()
        board.addPath(rounded(24, 22, 72, 52, 10))
        board.addEllipse(in: CGRect(x: 60 - 17, y: 48 - 17, width: 34, height: 34))
        board.addEllipse(in: CGRect(x: 60 - 6, y: 48 - 6, width: 12, height: 12))
        let bracket = rounded(4, 10, 12, 80, 4)
        let contacts = rounded(38, 78, 36, 12, 3)
        return [
            Piece(path: board, evenOdd: true),
            Piece(path: bracket, evenOdd: false),
            Piece(path: contacts, evenOdd: false),
        ]
    }

    /// A memory stick: a solid board with two chips' worth of slots cut out,
    /// and a row of contacts below it.
    private static var memoryGlyph: [Piece] {
        let board = CGMutablePath()
        board.addPath(rounded(6, 20, 88, 50, 9))
        board.addPath(rounded(20, 33, 22, 24, 4))
        board.addPath(rounded(58, 33, 22, 24, 4))
        let contacts = CGMutablePath()
        for x: CGFloat in [14, 34, 54, 74] {
            contacts.addPath(rounded(x, 76, 12, 18, 3))
        }
        return [Piece(path: board, evenOdd: true), Piece(path: contacts, evenOdd: false)]
    }

    /// A thermometer: a solid stem and bulb, with the stem's bore cut out
    /// above the bulb so it reads as glass rather than as a key.
    private static var temperatureGlyph: [Piece] {
        let glass = CGMutablePath()
        glass.addPath(rounded(36, 4, 28, 64, 14))
        glass.addPath(rounded(45, 14, 10, 40, 5))
        let bulb = CGPath(ellipseIn: CGRect(x: 50 - 23, y: 52, width: 46, height: 46), transform: nil)
        return [Piece(path: glass, evenOdd: true), Piece(path: bulb, evenOdd: false)]
    }
}
