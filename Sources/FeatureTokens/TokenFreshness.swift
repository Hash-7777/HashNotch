import Foundation

/// How old the token figure is, in words.
///
/// It used to say "counted 5 min ago", and the first word was doing no work.
/// The row it sits on already says AI tokens, carries the count's own mark, and
/// puts the figure directly beside these words with the button that counts
/// again next to that — so "counted" was a label on something nothing else
/// could have been. What is left is the part that is actually news: the age.
///
/// The age stays, in some form, on every version of this row. A figure that
/// might be an hour old with nothing saying so is a figure that quietly
/// misleads, and this one can be: the scan is deliberately gated on the panel
/// being open, so a shut panel counts nothing.
///
/// Pure, and separate from the view, because it is a decision about wording
/// rather than about drawing — the sort of thing that used to sit inside a
/// view body here and go unchecked.
package enum TokenFreshness {
    /// Word for a count taken `countedAt`, as of `now`.
    ///
    /// The order of the two guards is deliberate and unchanged: never having
    /// counted is answered before counting-right-now, so the very first scan
    /// says the truthful "not yet" rather than promising a number that has
    /// never existed.
    package static func text(countedAt: Date?, isCounting: Bool, now: Date) -> String {
        guard let countedAt else { return "not yet" }
        if isCounting { return "counting…" }
        // A clock that went backwards — a manual time change, or a wake from
        // sleep — must not produce "-3 min ago". Anything not yet a minute old,
        // including the future, is "just now".
        let seconds = Int(now.timeIntervalSince(countedAt))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60)h ago"
    }
}
