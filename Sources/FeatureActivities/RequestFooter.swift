import Foundation

/// What, if anything, belongs under a request standing on the notch.
///
/// This existed as two lines of `if` inside a view body, and it was wrong. The
/// rule it encoded was "no answer token means answering must be switched off",
/// and a notice from an agent never carries a token — it is telling you
/// something, not asking which tool to run. So every "Claude needs you" came
/// with "Answering here is off. Turn it on in Settings, under Agents" printed
/// underneath it, while all four switches were on and the file behind them was
/// exactly right.
///
/// That is the worst kind of wrong message: it names a real setting, sends
/// somebody to a page where everything is already as it says it should be, and
/// leaves them with nothing to do and no reason given. A message that says a
/// feature is off is a claim about the feature, so it has to be read from the
/// feature.
package enum RequestFooter: Equatable {
    /// A tool is waiting on a decision, filed under this token.
    case answer(token: String)
    /// Nothing is waiting, and nothing is switched on to wait with. Worth
    /// saying once, under something that could have been answered here.
    case offerToTurnItOn
    case nothing

    /// - Parameters:
    ///   - token: the answer token, when this is a question rather than a notice.
    ///   - standing: whether this waits on the person rather than passing by.
    ///   - toolsChosen: how many tools are ticked in Settings, Agents.
    package static func under(
        token: String?,
        standing: Bool,
        toolsChosen: Int
    ) -> RequestFooter {
        if let token { return .answer(token: token) }
        // A notice that dismisses itself is not owed anything.
        guard standing else { return .nothing }
        // The offer is only an offer while there is something to accept. With
        // tools already chosen, this notice simply is not a question, and
        // saying anything about answering here would be answering a question
        // nobody asked.
        return toolsChosen == 0 ? .offerToTurnItOn : .nothing
    }
}
