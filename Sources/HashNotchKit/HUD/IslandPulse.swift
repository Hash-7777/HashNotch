import Foundation

/// How the coloured line breathes, and how that changes as something waits.
///
/// A steady ring is easy to stop seeing, so the line breathes. The longer
/// something has been waiting on you, the shorter that breath and the less the
/// line fades on the way — the difference between a light that is on and one
/// that is asking.
///
/// Both ends are deliberately gentle. This is the entire escalation the app
/// does: no growing, no second alert, no sound. Something you have not dealt
/// with should press a little harder, not shout, because an alert that shouts
/// is one people learn to hide.
package enum IslandPulse {
    /// Seconds for one breath, in and out.
    package static func period(urgency: Double) -> Double {
        1.4 - 0.6 * clamped(urgency)
    }

    /// How far the line dims at the bottom of a breath, where 1 is not at all.
    package static func floor(urgency: Double) -> Double {
        0.55 + 0.25 * clamped(urgency)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
