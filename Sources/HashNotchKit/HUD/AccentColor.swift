import AppKit
import SwiftUI

/// The accent colours the island can be tinted with.
///
/// A short, named list rather than a colour well: every one of these is chosen
/// to stay legible against solid black at eleven points, which an arbitrary
/// colour is not. The stored value is the id, so a palette can be re-tuned
/// later without invalidating anyone's saved choice.
public struct AccentColor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let color: Color

    public static let all: [AccentColor] = [
        AccentColor(id: "blue", name: "Blue", color: Color(red: 0.25, green: 0.55, blue: 1.00)),
        AccentColor(id: "green", name: "Green", color: Color(red: 0.28, green: 0.84, blue: 0.48)),
        AccentColor(id: "orange", name: "Orange", color: Color(red: 1.00, green: 0.62, blue: 0.20)),
        AccentColor(id: "pink", name: "Pink", color: Color(red: 1.00, green: 0.40, blue: 0.62)),
        AccentColor(id: "purple", name: "Purple", color: Color(red: 0.68, green: 0.48, blue: 1.00)),
        AccentColor(id: "white", name: "White", color: Color.white),
    ]

    /// Orange, not the first in the list.
    ///
    /// Named rather than indexed so the swatch order and the default are
    /// separate decisions — reordering the palette should not silently change
    /// what everybody sees on a fresh install. Orange because the island is
    /// black and sits against whatever wallpaper somebody has: a warm accent
    /// holds against both a bright photograph and a dark one, where blue drops
    /// into the dark and disappears on half of them. Falls back to the first
    /// swatch if the id ever stops existing, so this cannot become nil.
    public static let `default` = all.first { $0.id == "orange" } ?? all[0]

    /// Rec. 601 luma, which weights green far above blue because the eye does.
    /// A plain average would call this app's blue light and its green dark,
    /// which is the wrong way round.
    package var isLight: Bool {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) > 0.62
    }

    public static func named(_ id: String) -> AccentColor {
        all.first { $0.id == id } ?? .default
    }
}
