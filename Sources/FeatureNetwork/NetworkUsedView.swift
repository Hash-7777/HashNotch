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
            full: NetworkUsedMath.drawableWidth(Panel.rowWidth),
            floor: NetworkUsedMath.minimumSegment)
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.textColor.opacity(0.08))
                .frame(width: Panel.rowWidth, height: NetworkUsedMath.barHeight)
            // Two shapes with dark between them, rather than one shape cut in
            // two. Each half is rounded at both ends and owns its own edges.
            HStack(spacing: NetworkUsedMath.segmentGap) {
                Capsule().fill(theme.downColor.opacity(NetworkUsedMath.barOpacity))
                    .frame(width: widths.down)
                Capsule().fill(theme.upColor.opacity(NetworkUsedMath.barOpacity))
                    .frame(width: widths.up)
            }
            .frame(height: NetworkUsedMath.barHeight)
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

    /// How strongly the total's own bar is drawn.
    ///
    /// Softened from full strength, along with the gap below, because the two
    /// halves are a green and a red and those are the worst two colours in the
    /// panel to put edge to edge. At full saturation the shared boundary
    /// shimmers, and the red half reads as though it were drawn taller than the
    /// green one — it is not, both are 3.5 points to the pixel, measured — which
    /// is what an eye does with two saturated complements meeting on black.
    package static let barOpacity: Double = 0.72

    /// The dark gap between the two halves.
    ///
    /// The real fix for the above: with a gap, the two never share an edge,
    /// there is nothing to shimmer, and each half is its own rounded shape that
    /// cannot borrow apparent height from its neighbour. It also survives being
    /// unable to tell red from green — the commonest colour blindness there is,
    /// and exactly this pair — because two separated lengths are still two
    /// lengths, and the figures beneath carry their own arrows.
    /// Two points. The rounded ends of the two halves taper into it, so the
    /// dark it actually reads as is wider than the number — measured at eight
    /// points of apparent gap for three of real one, which is three per cent of
    /// the bar and enough to start flattering whichever half is smaller.
    package static let segmentGap: CGFloat = 2

    /// How tall one program's row is drawn.
    ///
    /// Each row IS its bar now — the figures sit on top of a length that says
    /// how this program compares with the biggest — rather than being a row of
    /// text with a separate hairline underneath it. Three programs used to mean
    /// three more bars stacked under the one they were a breakdown of, and four
    /// bars in a block eighty points tall is a chart nobody asked for.
    package static let breakdownRowHeight: CGFloat = 16

    /// And how faintly that length is filled.
    ///
    /// Quiet enough to read a name across, and quiet enough that the list stays
    /// visibly subordinate to the figure above it. The relationship is the
    /// point: this is a breakdown, and a breakdown drawn as loudly as the total
    /// reads as a second set of readings.
    package static let breakdownFillOpacity: Double = 0.2

    /// How wide each half of the bar is drawn.
    ///
    /// The two always come to exactly the full width when anything has gone
    /// through, so the bar cannot end with a gap in it or overrun its track.
    /// When a share is too small to see, the floor is taken OUT of the other
    /// segment rather than added on top.
    /// The room the two halves have between them, once the gap is taken out.
    package static func drawableWidth(_ full: CGFloat) -> CGFloat {
        max(full - segmentGap, 0)
    }

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


/// One program, drawn as the length it used.
///
/// **Why the row is the bar.** The list used to be a name and two figures with
/// a hairline bar underneath each — which put four bars in the block once the
/// total's own is counted, stacked one under another, none of them the same
/// kind of thing as its neighbour. Giving each row a filled length instead
/// makes the comparison the shape of the row itself: the longest row is the
/// program that used the most, readable without reading a single figure, and
/// there is one bar in the block again.
///
/// The length is this program against the BIGGEST in the list rather than
/// against the total. A share of the total is a sliver for everything below
/// first place, and a list of slivers compares nothing; the ratios between
/// programs are identical either way.
///
/// **One colour, not two.** The fill was split into the same down and up
/// colours as the bar above it, and it had to stop: at this height the split
/// runs directly underneath the figure on the right, so a number sat half on
/// green and half on red — hard to read, and reading as though it belonged to
/// the red half. The block above already answers which way the traffic went.
/// The question this list answers is "which program", which is a question about
/// size, and size is one length in one colour. The exact split for a single
/// program is one hover away.
///
/// The colour is the accent, so it follows whatever the panel has been set to
/// and is plainly a different dimension from the two directions.
struct NetworkAppRow: View {
    let app: AppUsageShare
    /// The largest in the list, which every row is drawn against.
    let biggest: UInt64
    let theme: Theme

    var body: some View {
        let width = NetworkAppUsageMath.barWidth(
            total: app.total, biggest: biggest,
            full: Panel.rowWidth, floor: NetworkUsedMath.minimumSegment * 2)
        return ZStack(alignment: .leading) {
            // A track under everything, so a short row still starts from
            // somewhere rather than floating in the dark.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.textColor.opacity(0.05))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.accent.opacity(NetworkUsedMath.breakdownFillOpacity))
                .frame(width: width)
            HStack(spacing: 8) {
                Text(app.name)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                    // From the middle, because a program name that has been cut
                    // is usually still recognisable at both ends and rarely at
                    // one.
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Formatters.bytes(Int64(clamping: app.total)))
                    .foregroundStyle(theme.subtitleColor)
                    .monospacedDigit()
                    .rollingDigits()
                    .layoutPriority(1)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
        }
        .frame(width: Panel.rowWidth, height: NetworkUsedMath.breakdownRowHeight)
        .help("\(Formatters.bytes(Int64(clamping: app.received))) came down, \(Formatters.bytes(Int64(clamping: app.sent))) went up")
        .animation(.snappy, value: app.total)
    }
}
