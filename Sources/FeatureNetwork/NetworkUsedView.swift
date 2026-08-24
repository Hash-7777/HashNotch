import SwiftUI
import HashNotchKit

/// How much has gone through, over the span the settings ask for.
///
/// **Why this is not the speed row again.** It sat directly beneath the speed
/// row and was drawn as the same object — same label, same pair of arrows and
/// figures, same colours at the same size — and two rows drawn identically say
/// they are the same kind of reading. A speed is a rate, true for this instant
/// and moving both ways; a total only ever grows, and is asked about once a
/// day. What separates them now is the mark in front of the words — a rising
/// set of bars against the speed row's globe — the unit on the figures, and the
/// space between them: the two directions sit at opposite ends of the row
/// rather than side by side, because they are two answers and not one pair.
///
/// It had a headline total and a bar dividing that total into the two
/// directions. Both are gone at the owner's request: the two figures are what
/// he wants read, and a total of them is arithmetic anybody can do at a glance
/// with two numbers on one line.
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

    var body: some View {
        // Six rather than eight between the pieces, and four as the least a
        // spacer may be. This row carries up to six things — a mark, a name, a
        // warning, two figures and a button — and at eight points apiece the
        // gaps alone were costing it a figure.
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                NotchIconView(.dataUsed, size: 11, color: theme.subtitleColor)
                Text("Used \(periodCaption)")
                    .foregroundStyle(theme.subtitleColor)
                    .lineLimit(1)
                    // The name may give up a sixth of its size, and no more.
                    //
                    // Every other row in the panel holds its name at full size
                    // and takes any shortfall out of the trailing side, because
                    // there the trailing side is a sentence that can lose its
                    // tail. Here it is two figures, and a figure cannot lose
                    // anything at all. So this one row shares the squeeze:
                    // "Used this month" beside 914 GB and 149 GB, with a
                    // warning mark and a reset button, is genuinely more than
                    // 260 points of row, and something has to give. A name a
                    // sixth smaller is still a name. A number missing its last
                    // digits is not a number.
                    .minimumScaleFactor(0.84)
                .layoutPriority(0)
            }
            // Whatever has to be admitted about the figures is admitted beside
            // them, as a mark rather than as a line of small print underneath —
            // small print would change the height of the row depending on how
            // much data somebody had used. The sentence is one hover away.
            if let note {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
                    .help(note)
            }
            // Two spacers rather than one, so the two directions are pushed
            // apart instead of huddling at the right-hand end. They are two
            // separate answers — how much came down, how much went up — and
            // reading them as a pair is what made this row look like the speed
            // row above it.
            Spacer(minLength: 4)
            amount("arrow.down", received, theme.downColor)
            Spacer(minLength: 4)
            amount("arrow.up", sent, theme.upColor)
            // A span counted from the beginning of a day or a month starts
            // itself; this one has to be started by hand, and the button belongs
            // beside the figures it clears rather than in a settings window two
            // clicks away from them.
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
        .frame(width: Panel.rowWidth)
    }

    /// One direction: the arrow, and the figure.
    ///
    /// **The figures are served before the gaps are.** Without that, they are
    /// not: a spacer is endlessly flexible and so is a line of text, so SwiftUI
    /// squeezed both together and took the shortfall out of the number. The row
    /// showed "30.5…" for thirty and a half megabytes, and with a longer span
    /// and a reset button on it, "9…" for nine hundred and fourteen gigabytes.
    /// A truncated figure is the one thing this panel must never show — a label
    /// can be inferred from the row it is on, and a number cannot be inferred
    /// from anything.
    ///
    /// The priority is on the whole pair rather than on the text inside it,
    /// which is where it was and why it did nothing: a priority settles a
    /// contest inside its own stack, and the contest here is in the row.
    private func amount(_ symbol: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(Formatters.bytes(Int64(clamping: bytes)))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .rollingDigits()
                .animation(.snappy, value: bytes)
                .lineLimit(1)
                // And if it still will not fit — a month of traffic, a warning
                // mark and a reset button all on one row — it gives up a fifth
                // of its size rather than its last digits. Smaller is still
                // readable. Cut is not.
                .minimumScaleFactor(0.8)
        }
        .layoutPriority(1)
    }
}

/// What the per-program list needs to draw itself.
package enum NetworkUsedMath {
    /// How tall one program's row is drawn.
    ///
    /// Each row IS its bar — the figures sit on top of a length that says how
    /// this program compares with the biggest — rather than being a row of text
    /// with a separate hairline underneath it.
    package static let breakdownRowHeight: CGFloat = 16

    /// And how faintly that length is filled: quiet enough to read a name
    /// across, and quiet enough that the list stays visibly subordinate to the
    /// figures above it.
    package static let breakdownFillOpacity: Double = 0.2

    /// The shortest a length is drawn while it stands for anything at all. A
    /// program that used a thousandth of what the biggest one did still used
    /// something, and "nothing" is the one answer that is plainly false.
    package static let minimumSegment: CGFloat = 2
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
