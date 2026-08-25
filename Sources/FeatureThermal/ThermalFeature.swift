import SwiftUI
import HashNotchKit

/// How the temperature readout is shown.
package enum ThermalStyle: String {
    case symbolAndNumber
    case number
    case word
    case symbol
}

/// Temperature as a plain word, for people who would rather not read numbers to
/// find out whether their Mac is hot.
///
/// Thresholds picked for silicon rather than for weather: an Apple Silicon die
/// idles in the forties and is entirely happy in the sixties, so the words a
/// thermostat would use are all wrong here.
package enum ThermalWording {
    package static func word(for celsius: Double) -> String {
        switch celsius {
        case ..<50: return "Cool"
        case ..<70: return "Warm"
        case ..<85: return "Hot"
        default: return "Very hot"
        }
    }
}

/// System temperature, shown to the right of the notch by default.
@MainActor
public final class ThermalFeature: NotchFeature {
    public let id = "thermal"
    public let title = "Temperature"
    public let placement: FeaturePlacement = .trailing

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: ThermalStyle.symbolAndNumber.rawValue, title: "Symbol and number"),
        FeatureOption(id: ThermalStyle.number.rawValue, title: "Number only"),
        FeatureOption(id: ThermalStyle.word.rawValue, title: "Word (Cool / Warm)"),
        FeatureOption(id: ThermalStyle.symbol.rawValue, title: "Symbol only"),
    ]

    private let monitor = ThermalMonitor()

    public init() {}

    public func start(context: FeatureContext) { monitor.start(visibility: context.visibility, scale: context.settings.samplingScale) }
    public func stop() { monitor.stop() }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(ThermalDetailView(
            monitor: monitor,
            theme: context.theme,
            style: ThermalStyle(rawValue: context.settings.style(for: id)) ?? .symbolAndNumber
        ))
    }
}
