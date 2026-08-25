import SwiftUI

/// Tracks which features currently have something "live" to show always-on
/// (media playing, an activity in progress). When anything is live, the island
/// shows a slim compact strip below the notch even without hovering — like the
/// iPhone's compact Dynamic Island. Features signal in; the island observes.
@MainActor
public final class LivePresence: ObservableObject {
    @Published public private(set) var activeIDs: Set<String> = []

    /// Bumped when a feature that is ALREADY live says that what it wants the
    /// island to draw has changed.
    ///
    /// The island reads three things off whichever feature owns the strip — the
    /// colour of its edge, how hard that colour pulses, and how urgent the
    /// feature's claim to the strip is — and it reads them while building its
    /// body. A body is only rebuilt when something it observes changes, and the
    /// only thing it observes here is the set of live ids. So a feature could
    /// change ALL THREE and the island would never hear about it, as long as the
    /// feature stayed live throughout.
    ///
    /// Two things were broken by exactly that, and neither looked like the same
    /// bug from outside. A timer going off never lit the island's edge: it was
    /// already live while counting down, so reaching zero changed nothing the
    /// island watched — its own words changed, because the strip's views watch
    /// the countdown directly, but the edge and the claim on the strip did not.
    /// And a request left waiting never pressed any harder, for the same reason:
    /// the urgency it reports climbs with every second it waits, and nothing was
    /// asking it again.
    @Published public private(set) var revision: Int = 0

    public init() {}

    /// Say that a live feature's colour, urgency or claim has changed.
    ///
    /// Separate from `setActive` rather than folded into it, because the guard
    /// in `setActive` is worth keeping: a feature that reports the same state
    /// every second — and several do — must not redraw the island every second.
    /// This is the deliberate version, called when something has actually
    /// changed.
    ///
    /// Ignored for a feature that is not live, since nothing of it is on screen
    /// to change.
    public func changed(_ id: String) {
        guard activeIDs.contains(id) else { return }
        revision &+= 1
    }

    public var hasLive: Bool { !activeIDs.isEmpty }

    /// Development aid, off unless `HASHNOTCH_DEBUG` asks for it. Which
    /// features hold the strip is otherwise unobservable from outside the app —
    /// every live state gives the overlay window the same height, so no amount
    /// of measuring its frame can tell a song from an alert.
    private static let logsChanges =
        (ProcessInfo.processInfo.environment["HASHNOTCH_DEBUG"] ?? "").contains("live")

    public func setActive(_ id: String, _ active: Bool) {
        guard active != activeIDs.contains(id) else { return }
        if Self.logsChanges {
            FileHandle.standardError.write(Data(
                "[live] \(active ? "+" : "-")\(id) → \(activeIDs.union(active ? [id] : []).subtracting(active ? [] : [id]).sorted())\n".utf8
            ))
        }
        // Inside an animation transaction so the strip's content transition
        // (emerging from the notch) actually animates — a bare set would grow
        // the pill but pop the content in.
        withAnimation(
            active
                ? .spring(response: 0.45, dampingFraction: 0.82)
                : .spring(response: 0.38, dampingFraction: 0.95)
        ) {
            if active {
                activeIDs.insert(id)
            } else {
                activeIDs.remove(id)
            }
        }
    }
}
