import SwiftUI
import Combine
import HashNotchKit

/// How the speed reads. The same two numbers, arranged for different taste and
/// different amounts of room beside the notch.
enum NetworkStyle: String {
    /// Both figures stacked, up above down, in the width of one.
    case stacked
    /// Both on one line, separated by a dot, with no arrows.
    case compact
    /// The shape of the last half-minute, up and down overlaid.
    case graph
    case both
    case downloadOnly
    case uploadOnly
}

/// Live internet throughput. Defaults to the left of the notch, keeping the
/// right side (battery, temperature) narrow and clear of the system status
/// icons. Users can move it to either side in Settings.
@MainActor
public final class NetworkFeature: NotchFeature {
    public let id = "network"
    public let title = "Internet speed"
    public let placement: FeaturePlacement = .leading

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: NetworkStyle.graph.rawValue, title: "Graph and speed"),
        FeatureOption(id: NetworkStyle.both.rawValue, title: "Up and down"),
        FeatureOption(id: NetworkStyle.downloadOnly.rawValue, title: "Download only"),
        FeatureOption(id: NetworkStyle.uploadOnly.rawValue, title: "Upload only"),
        FeatureOption(id: NetworkStyle.stacked.rawValue, title: "Stacked"),
        FeatureOption(id: NetworkStyle.compact.rawValue, title: "Compact"),
    ]

    private let monitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(
            visibility: context.visibility,
            scale: context.settings.samplingScale,
            period: context.settings.networkUsagePeriod,
            showsApps: context.settings.networkShowsApps
        )

        // Followed live, not only when the panel is next drawn.
        //
        // Every other setting here can wait for the next draw, because until
        // then it changes nothing anybody can see. This one is a permission:
        // while it says off, a subprocess must not be being run that asks
        // which of your programs use the network. A switch that takes effect
        // when you next happen to open the panel is not off, it is off soon —
        // the same reasoning the cover-art switches are kept in step for.
        context.settings.$networkShowsApps
            .removeDuplicates()
            .sink { [weak self] shows in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.monitor.setShowsApps(shows) }
                }
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        monitor.stop()
    }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = NetworkStyle(rawValue: context.settings.style(for: id)) ?? .both
        return AnyView(NetworkView(monitor: monitor, theme: context.theme, style: style))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        // The span is read here rather than held by the monitor alone, so a
        // change in settings reaches the figures the next time the panel is
        // drawn — which is before anybody can have seen the old ones.
        monitor.setPeriod(context.settings.networkUsagePeriod)
        return AnyView(NetworkDetailView(
            monitor: monitor,
            settings: context.settings,
            theme: context.theme,
            style: NetworkStyle(rawValue: context.settings.style(for: id)) ?? .both,
            period: context.settings.networkUsagePeriod
        ))
    }
}
