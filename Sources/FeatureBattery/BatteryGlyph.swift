import SwiftUI
import HashNotchKit

/// A battery drawn to the level it is actually at, the way the one in the menu
/// bar is.
///
/// A symbol cannot do this. `battery.100`, `battery.75`, `battery.50` and
/// `battery.25` are four pictures, so the nearest one has to be picked, and the
/// gap between the picture and the number beside it is up to twelve per cent —
/// a shape that says half full sitting next to the figure 57. The strip was
/// not even doing that: it drew `battery.100` for anything discharging, so the
/// outline was FULL at four per cent, and the panel drew no battery at all,
/// only a bolt or a pause. An indicator that disagrees with the number printed
/// beside it teaches people to stop reading the indicator.
///
/// So it is drawn rather than chosen: one rectangle whose width is the charge.
/// Nothing here is a picture of a battery at some level; it is the level.
struct BatteryGlyph: View {
    let percentage: Int
    let state: BatteryState
    let isLowPowerMode: Bool
    let theme: Theme

    /// How long the whole thing is for its height, nub included.
    ///
    /// Measured off Apple's own battery rather than chosen: `battery.100`,
    /// `battery.50` and `battery.0` all ink out at 58.00 x 26.33 points at 40pt,
    /// which is this. The first draft of this glyph was hand-picked at 22 by
    /// 10.5 with a nub on the end, which came to 2.362 — seven per cent longer
    /// than Apple's, and it read as a stretched battery sitting next to text
    /// that is drawn to Apple's proportions everywhere else on the row.
    private static let lengthForHeight: CGFloat = BatteryGlyphShape.lengthForHeight

    /// Everything else follows from the height, so the shape has ONE number to
    /// get right and cannot drift out of proportion a piece at a time.
    ///
    /// Eleven points, which is the size of the text it sits beside — a battery
    /// shorter than the words next to it is what makes a correct ratio still
    /// look long.
    private var height: CGFloat { BatteryGlyphShape.height }
    private var totalWidth: CGFloat { BatteryGlyphShape.totalWidth }
    private var capWidth: CGFloat { BatteryGlyphShape.capWidth }
    private var capGap: CGFloat { BatteryGlyphShape.capGap }
    private var width: CGFloat { BatteryGlyphShape.bodyWidth }
    private var capHeight: CGFloat { height * 0.40 }
    /// The gap between the shell and the charge inside it.
    private var inset: CGFloat { height * 0.152 }

    var body: some View {
        HStack(spacing: capGap) {
            ZStack(alignment: .leading) {
                // The shell. Quiet, because it is the frame and not the
                // reading — the same relationship the menu bar's has.
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .strokeBorder(theme.textColor.opacity(0.38), lineWidth: 1)
                    .frame(width: width, height: height)

                // The charge. Its WIDTH is the number, which is the whole
                // point of drawing this rather than picking a picture of it.
                RoundedRectangle(cornerRadius: (height - inset * 2) * 0.34, style: .continuous)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: height - inset * 2)
                    .padding(.leading, inset)

                // The bolt goes over the charge while it is filling, exactly as
                // macOS does it, so "charging" is legible without reading the
                // words underneath.
                if state == .charging || state == .charged {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.62, weight: .bold))
                        .foregroundStyle(theme.textColor)
                        // A black rim, so the bolt reads whether it is sitting
                        // on the filled part or the empty part. Without it, it
                        // vanishes into the fill at one level and into the dark
                        // at another.
                        .shadow(color: .black.opacity(0.65), radius: 0.8)
                        .frame(width: width, height: height)
                }

                // Held at a ceiling for battery health: not charging, not
                // running down. A pause rather than a bolt, because a bolt on a
                // battery that has deliberately stopped filling is the one
                // thing it must not say.
                if state == .onHold {
                    Image(systemName: "pause.fill")
                        .font(.system(size: height * 0.52, weight: .bold))
                        .foregroundStyle(theme.textColor)
                        .shadow(color: .black.opacity(0.65), radius: 0.8)
                        .frame(width: width, height: height)
                }
            }
            .frame(width: width, height: height)

            // The nub on the end. Drawn at the same weight as the shell, since
            // it is part of the same outline.
            RoundedRectangle(cornerRadius: capWidth * 0.45, style: .continuous)
                .fill(theme.textColor.opacity(0.38))
                .frame(width: capWidth, height: capHeight)
        }
        // The charge slides to a new level rather than jumping to it, which is
        // what makes it read as a quantity rather than as a redraw.
        .animation(.snappy, value: percentage)
        .animation(.snappy, value: state)
        .animation(.snappy, value: isLowPowerMode)
        .accessibilityLabel(accessibilityText)
    }

    /// How wide the charge is drawn.
    ///
    /// Clamped to the shell at the top, and given a floor at the bottom, so an
    /// almost-flat battery still shows a sliver instead of nothing. A shell
    /// drawn empty is indistinguishable from a shell drawn broken, and at 1%
    /// the truthful thing to say is "nearly none", not "none".
    private var fillWidth: CGFloat {
        let usable = width - inset * 2
        let level = CGFloat(min(max(percentage, 0), 100)) / 100
        return max(usable * level, level > 0 ? 2 : 0)
    }

    /// What colour the charge is, following macOS: green on the charger, yellow
    /// in Low Power Mode, red when it is nearly out, and otherwise the ordinary
    /// text colour — a battery that is simply fine should not be shouting a
    /// colour at anybody.
    ///
    /// Low Power Mode outranks the level, because when both are true the more
    /// useful sentence is "the reason this feels different is a setting".
    private var fillColor: Color {
        if isLowPowerMode { return .yellow }
        switch state {
        case .charging, .charged: return theme.downColor
        case .onHold: return theme.textColor.opacity(0.8)
        case .discharging:
            if percentage <= 10 { return theme.upColor }
            if percentage <= 20 { return .orange }
            return theme.textColor
        }
    }

    private var accessibilityText: String {
        switch state {
        case .charging: return "Battery \(percentage) percent, charging"
        case .charged: return "Battery full, on power"
        case .onHold: return "Battery \(percentage) percent, held on power"
        case .discharging: return "Battery \(percentage) percent"
        }
    }
}

/// The battery's proportions, on their own so the checks can hold them to the
/// measurement rather than leaving the shape to be re-judged by eye every time
/// somebody touches it.
///
/// The view above is a view and cannot be reached from a framework-free checks
/// target; these are the numbers that decide whether it looks like a battery.
package enum BatteryGlyphShape {
    /// How long the whole thing is for its height, nub included — Apple's own,
    /// measured off `battery.100`, `battery.50` and `battery.0`, which all ink
    /// out at 58.00 x 26.33 points.
    package static let lengthForHeight: CGFloat = 2.203
    /// The size of the text it sits beside.
    package static let height: CGFloat = 11
    package static var totalWidth: CGFloat { height * lengthForHeight }
    package static var capWidth: CGFloat { height * 0.155 }
    package static var capGap: CGFloat { height * 0.1 }
    package static var bodyWidth: CGFloat { totalWidth - capWidth - capGap }
}
