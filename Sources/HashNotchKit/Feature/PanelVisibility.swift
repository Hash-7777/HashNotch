import Foundation

/// Whether the drop-down panel is open, shared with every feature.
///
/// Most readouts — internet speed, temperatures, tokens, AirPods — are only
/// ever drawn inside the panel. Sampling them while it is shut spends battery
/// computing numbers nobody can see, and for some of them a whole subprocess or
/// a walk of a directory tree. Features that live in the panel watch this and
/// sample only while it is open.
///
/// This is the mirror image of `LivePresence`: presence is a feature telling
/// the island it has something to show, visibility is the island telling
/// features whether anyone is looking.
@MainActor
public final class PanelVisibility: ObservableObject {
    @Published public private(set) var isOpen: Bool = false

    public init() {}

    public func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
    }
}
