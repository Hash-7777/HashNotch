import SwiftUI
import HashNotchKit

/// Compact-live: a download glyph left of the notch when a file just finished.
struct DownloadsIconView: View {
    @ObservedObject var monitor: DownloadsMonitor
    let theme: Theme

    var body: some View {
        if monitor.latest != nil {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Compact-live: the finished file's name, right of the notch.
struct DownloadsTextView: View {
    @ObservedObject var monitor: DownloadsMonitor
    let theme: Theme

    var body: some View {
        if let download = monitor.latest {
            MarqueeText(download.name)
                .foregroundStyle(theme.textColor)
                .frame(maxWidth: 140, alignment: .leading)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// A file-download finished notice for the notch — reads only the names in
/// your Downloads folder, never opens a file.
@MainActor
public final class DownloadsFeature: NotchFeature {
    public let id = "downloads"
    public let title = "Downloads"
    // A finished download is a six-second announcement, then gone.
    public let livePriority = LivePriority.announcement

    private let monitor = DownloadsMonitor()

    public init() {}

    // No away figure, and it is worth saying why rather than leaving the
    // absence to look like an oversight. This monitor re-seeds its baseline
    // from the folder every time it starts, deliberately, so that files already
    // there never announce themselves on launch — and a spell away stops and
    // restarts it. Anything that landed while the screen was off is therefore
    // seeded as already known and never counted. It could be made to survive by
    // watching the folder through a lock, and it should not be: nothing reads
    // anything while the screen is away, and that rule is worth more than this
    // line of a digest.

    public func start(context: FeatureContext) { monitor.start(presence: context.presence) }
    public func stop() { monitor.stop() }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(DownloadsIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(DownloadsTextView(monitor: monitor, theme: context.theme))
    }
}
