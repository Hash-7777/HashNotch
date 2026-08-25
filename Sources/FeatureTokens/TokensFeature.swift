import SwiftUI
import HashNotchKit

/// How the token readout is shown.
package enum TokensStyle: String {
    case number
    case labeled
}

/// Today's AI token usage, read from the same local files as HashMeterAi.
@MainActor
public final class TokensFeature: NotchFeature {
    public let id = "tokens"
    public let title = "AI tokens"

    /// The first option is what a fresh install gets, and it is the one that
    /// says when the figure was taken.
    ///
    /// It was the other way round, which meant a new install showed a token
    /// count with nothing saying how old it was — and that count is not live.
    /// It is taken on a schedule the reader chooses, and can be set to no
    /// schedule at all, so an hour-old figure presented as though it were
    /// current is the one thing this row must not do by default. Anybody who
    /// would rather see the number alone can still say so, and then the age is
    /// a hover away.
    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: TokensStyle.labeled.rawValue, title: "Number and when it was counted"),
        FeatureOption(id: TokensStyle.number.rawValue, title: "Number only"),
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

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(TokensDetailView(
            monitor: monitor,
            theme: context.theme,
            style: TokensStyle(rawValue: context.settings.style(for: id)) ?? .labeled
        ))
    }
}
