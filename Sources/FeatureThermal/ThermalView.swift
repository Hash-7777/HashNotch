import SwiftUI
import HashNotchKit

/// Compact thermal readout: a thermometer glyph tinted by pressure, plus the
/// hottest die temperature (falling back to the pressure word).

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
        switch celsius {
        case ..<50: return theme.downColor
        case ..<70: return .yellow
        case ..<85: return .orange
        default: return theme.upColor
        }
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
                                    .foregroundStyle(theme.textColor)
                                    .monospacedDigit()
                                    .rollingDigits()
                            }
                        }
                    }
                    .animation(.snappy, value: sensor.celsius)
                }
            }
        }
    }
}
