import SwiftUI
import HashNotchKit

/// When a temperature counts as running high.
///
/// A temperature has no "100%", so it cannot use the shared share-of-the-whole
/// rule. It names its own point instead and answers with the same two levels:
/// the accent below it, red at and above it, and nothing in between.
package enum ThermalLevel {
    package static let hotCelsius = 80.0

    package static func level(_ celsius: Double) -> ReadingLevel {
        .of(celsius, dangerAt: hotCelsius)
    }
}

/// Expanded detail: the top temperature sensors, shown when the HUD opens.
struct ThermalDetailView: View {
    @ObservedObject var monitor: ThermalMonitor
    let theme: Theme
    let style: ThermalStyle

    /// A degree figure, or the plain word for people who would rather not read
    /// numbers to find out whether their Mac is hot.
    private func reading(_ celsius: Double) -> String {
        style == .word ? ThermalWording.word(for: celsius) : "\(Int(celsius.rounded()))°"
    }

    private func tint(for celsius: Double) -> Color {
        theme.color(for: ThermalLevel.level(celsius))
    }

    /// The figure stays white until it is running high, then takes the same
    /// red as its thermometer, so a hot reading is not only a small glyph.
    private func figureColor(for celsius: Double) -> Color {
        ThermalLevel.level(celsius) == .danger ? Theme.danger : theme.textColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotchSectionHeader("TEMPERATURE", icon: .temperature, theme: theme)

            if monitor.sensors.isEmpty {
                NotchRow("Pressure", theme: theme) {
                    Text(monitor.pressureLabel).foregroundStyle(theme.textColor)
                }
            } else {
                ForEach(monitor.sensors.prefix(5)) { sensor in
                    NotchRow(sensor.name, theme: theme) {
                        HStack(spacing: 5) {
                            if style == .symbol || style == .symbolAndNumber {
                                Image(systemName: "thermometer.medium")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(tint(for: sensor.celsius))
                            }
                            if style != .symbol {
                                Text(reading(sensor.celsius))
                                    .foregroundStyle(figureColor(for: sensor.celsius))
                                    .monospacedDigit()
                                    .rollingDigits()
                            }
                        }
                    }
                    .figureAnimation(.snappy, value: sensor.celsius)
                }
            }
        }
    }
}
