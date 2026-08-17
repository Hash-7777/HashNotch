import SwiftUI
import HashNotchKit

/// A countdown timer that lives in the notch: start it from the panel, watch
/// it flank the notch while it runs, get a chime when it ends.
@MainActor
public final class TimerFeature: NotchFeature {
    public let id = "timer"
    public let title = "Timer"
    public let placement: FeaturePlacement = .expanded

    private let engine = TimerEngine()

    public init() {}

    public func start(context: FeatureContext) { engine.start(presence: context.presence) }
    public func stop() { engine.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(TimerIconView(engine: engine, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(TimerTextView(engine: engine, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(TimerDetailView(engine: engine, theme: context.theme))
    }
}
