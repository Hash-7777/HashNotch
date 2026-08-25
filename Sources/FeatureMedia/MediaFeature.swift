import SwiftUI
import HashNotchKit

/// System-wide Now Playing media (music, video), shown in the notch like the
/// iPhone's Dynamic Island.
@MainActor
public final class MediaFeature: NotchFeature {
    public let id = "media"
    public let title = "Now playing"

    private let monitor = MediaMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(
            presence: context.presence,
            pressesKeys: { [settings = context.settings] in settings.canPressMediaKeys }
        )
    }

    public func stop() { monitor.stop() }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(MediaArtworkView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(MediaTitleView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard monitor.nowPlaying != nil else { return nil }
        return AnyView(MediaDetailView(
            monitor: monitor,
            theme: context.theme,
            onClose: context.closePanel,
            onOpenSettingsPage: context.openSettingsPage
        ))
    }

    /// Swipe sideways across the open panel to change track.
    ///
    /// Claimed only while something is actually PLAYING, not merely present. A
    /// paused track keeps the panel by design, so it is what is showing for
    /// most of the time the panel is open — and skipping a song somebody
    /// deliberately stopped, because their fingers drifted sideways while they
    /// read the battery row, is exactly the kind of thing a gesture must never
    /// do. Left goes forward, the direction the content moves.
    public func handleSwipe(_ direction: SwipeDirection) -> Bool {
        guard monitor.nowPlaying?.isPlaying == true else { return false }
        switch direction {
        case .left: monitor.next()
        case .right: monitor.previous()
        }
        return true
    }
}
