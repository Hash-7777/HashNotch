import Foundation
import SwiftUI

/// Says when the panel is in the middle of changing size, so that the readouts
/// inside it stop rolling their digits for as long as it is.
///
/// Every live figure in the app rolls its digits when it changes, and the panel
/// re-reads them once a second. Rolling is drawn as its own moving piece, laid
/// out where the figure was when the change began — which is right when the
/// figure is the only thing moving, and wrong when the row it belongs to is
/// moving at the same time. Stopping a focus stretch did both at once: the rows
/// slid up to close the gap, and every reading that happened to change in that
/// same tick was left behind in mid-air, over some other row, until it caught
/// up. It read as the panel falling apart and putting itself back together.
///
/// So while the panel is resizing, a figure that changes simply changes. The
/// digits roll again a moment later, when the only thing moving is the number.
@MainActor
public final class PanelMotion: ObservableObject {
    /// Whether a size change is under way.
    @Published public private(set) var isResizing = false

    private var settle: DispatchWorkItem?

    public init() {}

    /// Mark the panel as resizing for `seconds` — the length of the animation
    /// that is about to run, plus its settle.
    ///
    /// Called BEFORE the change it describes, in the same turn, so the rows are
    /// already told to hold their digits still in the very update that moves
    /// them. A later call extends the window rather than shortening it.
    public func beginResize(for seconds: TimeInterval) {
        isResizing = true
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.isResizing = false }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

extension EnvironmentValues {
    /// Read by `rollingDigits()`. Set by the island around everything it draws,
    /// so a feature's view needs to know nothing about this.
    package var panelIsResizing: Bool {
        get { self[PanelResizingKey.self] }
        set { self[PanelResizingKey.self] = newValue }
    }
}

private struct PanelResizingKey: EnvironmentKey {
    /// False everywhere else — the settings window draws rolling figures too,
    /// and nothing there moves under them.
    static let defaultValue = false
}
