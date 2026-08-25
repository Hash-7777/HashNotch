import Foundation

/// Which answered questions are still worth hiding.
///
/// The app files an answer; the ASKER owns the feed and removes its own
/// question. That is the right way round, and it means there is a gap between
/// pressing a button and the box going away — a gap that never closes at all if
/// the asker has already given up waiting and exited. Pressing a button and
/// watching nothing happen is how somebody presses it again.
///
/// So the panel hides it immediately and keeps hiding it until the question
/// actually leaves the feed. Pure, because the alternative is a set that grows
/// quietly inside a monitor and eventually becomes a record of what somebody
/// allowed — which this app has no business keeping.
package enum AnsweredQuestions {
    /// Forget tokens whose questions have gone; keep the ones still standing.
    package static func retained(_ answered: Set<String>, in fresh: [LiveActivity]) -> Set<String> {
        answered.intersection(Set(fresh.compactMap(\.asks)))
    }

    /// Whether this one has already been answered from the panel.
    package static func isHidden(_ activity: LiveActivity, answered: Set<String>) -> Bool {
        guard let token = activity.asks else { return false }
        return answered.contains(token)
    }
}
