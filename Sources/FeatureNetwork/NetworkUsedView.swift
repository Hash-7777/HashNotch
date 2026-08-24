import SwiftUI
import HashNotchKit

/// How much has gone through, over the span the settings ask for.
///
/// **Why this is not a row.** It was one, and it was drawn exactly like the
/// speed row directly above it: the same label on the left, the same pair of
/// arrows and figures on the right, in the same two colours at the same size.
/// Two rows that look identical say they are the same kind of thing, and these
/// two are not. Speed is a rate — true at this instant, gone by the next, and
/// it goes up and down. A total is an accumulation — it only ever grows, and it
/// answers a question you ask once a day rather than one you watch. Reading the
/// old panel meant reading both rows carefully enough to notice that one said
/// MB/s and the other GB, and until you did, the second row looked like a
/// second opinion about your connection.
///
/// So it is a different shape rather than a different colour: one figure large
/// enough to be the answer, a bar showing what that figure is made of, and the
/// two parts named underneath it. Nothing about it can be mistaken for the row
/// above, and it is read in the order it is asked about — how much, then which
/// way.
///
/// **Why the bar is a split and not a fill.** A bar that fills up says there is
/// something to fill: a limit, an allowance, a plan. This app knows of no such
/// number, and drawing a fill would invent one — somebody at three quarters of a
/// bar would reasonably think they were three quarters of the way to something.
/// The bar divides the total into what came down and what went up, which is a
/// fact the app actually has, and it is the same picture the per-program bars
/// underneath already use — so the block reads as the parent of the list below
/// it rather than as another entry in it.
///
/// It takes plain numbers rather than the monitor, so the checks can measure
/// what it does and it can be drawn without a Mac's network being read.
struct NetworkUsedView: View {
    let received: UInt64
    let sent: UInt64
    /// "today", "this month", "since reset".
    let periodCaption: String
    /// What has to be admitted about these figures, or nothing when they are
    /// whole.
    let note: String?
    /// Offered only for the span that has to be started by hand.
    let onReset: (() -> Void)?
    let theme: Theme

    private var total: UInt64 { received &+ sent }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            headline
            bar
            parts
        }
        .frame(width: Panel.rowWidth)
        .animation(.snappy, value: total)
    }

    /// The answer, and the mark that says what it is an answer to.
    private var headline: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                NotchIconView(.dataUsed, size: 11, color: theme.subtitleColor)
                Text("Used \(periodCaption)")
                    .foregroundStyle(theme.subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            // Whatever has to be admitted about the figure is admitted beside
            // it, as a mark rather than as a line of small print underneath —
            // small print would change the height of the block depending on how
            // much data somebody had used. The sentence is one hover away.
            if let note {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
                    .help(note)
            }
            Text(Formatters.bytes(Int64(clamping: total)))
                // Larger than the rows around it, because it is a summary of
                // them rather than one of them — and because being larger is
                // what stops it being read as another speed.
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            // A span counted from the beginning of a day or a month starts
            // itself; this one has to be started by hand, and the button belongs
            // beside the figure it clears rather than in a settings window two
            // clicks away from it.
            if let onReset {
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.subtitleColor)
                }
                .buttonStyle(.plain)
                .help("Start counting again from now")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    /// What the figure above is made of.
    private var bar: some View {
        let widths = NetworkUsedMath.segmentWidths(
            received: received, sent: sent,
            full: Panel.rowWidth, floor: NetworkUsedMath.minimumSegment)
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.textColor.opacity(0.08))
                .frame(width: Panel.rowWidth, height: NetworkUsedMath.barHeight)
            HStack(spacing: 0) {
                Rectangle().fill(theme.downColor.opacity(0.8))
                    .frame(width: widths.down)
                Rectangle().fill(theme.upColor.opacity(0.8))
                    .frame(width: widths.up)
            }
            .frame(height: NetworkUsedMath.barHeight)
            .clipShape(Capsule())
        }
        .frame(width: Panel.rowWidth, height: NetworkUsedMath.barHeight)
        .help("\(Formatters.bytes(Int64(clamping: received))) came down, \(Formatters.bytes(Int64(clamping: sent))) went up")
    }

    /// The two parts, each under the segment of the bar it belongs to.
    private var parts: some View {
        HStack(spacing: 8) {
            amount("arrow.down", received, theme.downColor)
            Spacer(minLength: 8)
            amount("arrow.up", sent, theme.upColor)
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
    }

    private func amount(_ symbol: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(color)
            Text(Formatters.bytes(Int64(clamping: bytes)))
                .foregroundStyle(theme.subtitleColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: bytes)
        }
    }
}

/// The arithmetic behind the split bar, kept out of the view so it can be
/// measured.
package enum NetworkUsedMath {
    /// Heavier than the per-program bars underneath — the thing a list is a
    /// breakdown of should not be the thinner line — and no heavier than it has
    /// to be. At four points and full strength it was the brightest thing in
    /// the block, which puts a picture above the figure it is a picture of.
    package static let barHeight: CGFloat = 3.5

    /// The shortest a segment is drawn while it stands for anything at all.
    ///
    /// A day where one direction is a thousandth of the other would otherwise
    /// draw that direction as nothing, and "nothing" is the one thing it is
    /// not. Two points overstates a very small share, which is why the exact
    /// figure for each direction is printed directly underneath: the bar is
    /// there to be glanced at, and the numbers under it are the answer.
    package static let minimumSegment: CGFloat = 2

    /// How heavy the per-program bars underneath are drawn. Kept here, beside
    /// the bar they are a breakdown of, so the two cannot be changed apart —
    /// the whole point of the pair is that one is visibly the parent of the
    /// other.
    package static let breakdownBarHeight: CGFloat = 2.5

    /// How wide each half of the bar is drawn.
    ///
    /// The two always come to exactly the full width when anything has gone
    /// through, so the bar cannot end with a gap in it or overrun its track.
    /// When a share is too small to see, the floor is taken OUT of the other
    /// segment rather than added on top.
    package static func segmentWidths(
        received: UInt64,
        sent: UInt64,
        full: CGFloat,
        floor: CGFloat
    ) -> (down: CGFloat, up: CGFloat) {
        let total = received &+ sent
        guard total > 0, full > 0 else { return (0, 0) }
        var down = full * NetworkAppUsageMath.downShare(received: received, total: total)
        if received > 0, down < floor { down = min(floor, full) }
        if sent > 0, full - down < floor { down = max(full - floor, 0) }
        return (down, full - down)
    }
}
