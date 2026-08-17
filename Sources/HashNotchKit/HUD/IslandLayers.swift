import Foundation

/// Which of the island's layers may be on screen at once.
///
/// The app's central promise about its own appearance is that there are three
/// states and it is only ever in one of them. That promise used to live in
/// whichever `@State` flag happened to be set correctly at the time, spread
/// across an exit animation, a delayed hand-off, an `onAppear`, and two
/// `onChange` handlers — and a report of the strip sitting beside the open
/// panel is what it looks like when one of them falls behind.
///
/// It is a pure function here so the rule can be checked rather than trusted:
/// the failure needs a live activity arriving in the same fraction of a second
/// as the panel opening, which is not a thing a person can stage reliably.
package enum IslandLayers {
    /// Whether the live strip is put on screen.
    ///
    /// `liveShown` is the strip's own sequencing flag — it is what waits for a
    /// closing panel to finish retracting before the strip emerges. It is
    /// deliberately NOT the last word: the panel wins outright, because the two
    /// are different shapes holding different layouts and the strip is the
    /// wider of the two, so it does not even hide behind the panel. The artwork
    /// juts out one side and the title the other.
    package static func stripIsVisible(liveShown: Bool, panelExpanded: Bool) -> Bool {
        liveShown && !panelExpanded
    }

    /// Whether the arrangement the app promises never to show is on screen.
    ///
    /// Used by the checks to state the promise directly, rather than inferring
    /// it from the positive case.
    package static func showsBothStripAndPanel(
        liveShown: Bool,
        panelExpanded: Bool
    ) -> Bool {
        stripIsVisible(liveShown: liveShown, panelExpanded: panelExpanded) && panelExpanded
    }
}
