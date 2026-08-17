import SwiftUI

/// Tracks which features currently have something "live" to show always-on
/// (media playing, an activity in progress). When anything is live, the island
/// shows a slim compact strip below the notch even without hovering — like the
/// iPhone's compact Dynamic Island. Features signal in; the island observes.
@MainActor
public final class LivePresence: ObservableObject {
    @Published public private(set) var activeIDs: Set<String> = []

    public init() {}

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
