import SwiftUI
import HashNotchKit

/// How the token readout is shown.
enum TokensStyle: String {
    case number
    case labeled
}

/// Today's AI token usage, read from the same local files as HashMeterAi.
@MainActor
public final class TokensFeature: NotchFeature {
    public let id = "tokens"
    public let title = "AI tokens"
    public let placement: FeaturePlacement = .leading

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: TokensStyle.number.rawValue, title: "Number only"),
        FeatureOption(id: TokensStyle.labeled.rawValue, title: "Number and \"today\""),
    ]

    private let monitor = TokensMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(
            scale: context.settings.samplingScale,
            interval: context.settings.tokenScanInterval
        )
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = TokensStyle(rawValue: context.settings.style(for: id)) ?? .number
        return AnyView(TokensView(monitor: monitor, theme: context.theme, style: style))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(TokensDetailView(
            monitor: monitor,
            theme: context.theme,
            style: TokensStyle(rawValue: context.settings.style(for: id)) ?? .labeled
        ))
    }
}
