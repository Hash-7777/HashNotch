import SwiftUI
import HashNotchKit

/// Compact battery readout. The style selects icon, percent, both, or the
/// estimated time remaining.
struct BatteryView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme
    let style: BatteryStyle

    var body: some View {
        HStack(spacing: 6) {
            if style != .percent {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
            if let text = valueText {
                Text(text)
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .rollingDigits()
                    .animation(.snappy, value: monitor.percentage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
        .opacity(monitor.hasBattery ? 1 : 0.4)
    }

    private var valueText: String? {
        switch style {
        case .icon:
            return nil
        case .percent, .iconAndPercent:
            return "\(monitor.percentage)%"
        case .timeRemaining:
            if let minutes = monitor.minutesRemaining, minutes > 0 {
                return Formatters.hoursMinutes(minutes)
            }
            return "\(monitor.percentage)%"
        }
    }

    private var symbolName: String {
        switch monitor.state {
        case .charging: return "bolt.fill"
        case .charged: return "battery.100percent.bolt"
        case .onHold: return "battery.100percent.bolt"
        case .discharging: return "battery.100"
        }
    }

    /// Low Power Mode paints the battery yellow, exactly as it does on iPhone,
    /// because the single most useful thing that indicator can say is "the
    /// reason this feels different is a setting, not a fault".
    private var symbolColor: Color {
        if monitor.isLowPowerMode { return .yellow }
        switch monitor.state {
        case .charging, .charged, .onHold: return theme.downColor
        case .discharging: return fillColor
        }
    }

    private var fillColor: Color {
        switch monitor.percentage {
        case ..<20: return theme.upColor
        case ..<50: return .orange
        default: return theme.downColor
        }
    }
}

/// Compact-live: a brief iPhone-style announcement flanking the notch when
/// the Mac starts charging or the battery runs low.
struct BatteryEventIconView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme

    var body: some View {
        if let event = monitor.event {
            Image(systemName: iconName(event))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor(event))
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// The symbol belongs to the announcement, not to whatever the battery
    /// happens to be doing while it is on screen — see `BatteryEvent.symbolName`
    /// for why asking the live state was wrong at precisely the moment it was
    /// asked.
    private func iconName(_ event: BatteryEvent) -> String { event.symbolName }

    private func iconColor(_ event: BatteryEvent) -> Color {
        switch event {
        case .pluggedIn, .fullyCharged: return theme.downColor
        case .lowBattery: return theme.upColor
        case .unplugged: return theme.subtitleColor
        }
    }
}

struct BatteryEventTextView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme

    var body: some View {
        if let event = monitor.event {
            Text(text(event))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .lineLimit(1)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func text(_ event: BatteryEvent) -> String {
        switch event {
        case .pluggedIn:
            // Four words, and nothing that can change while they are on screen.
            //
            // This used to read the live state and assemble the level, the
            // wattage, the charge speed and the time to full. Every one of
            // those settles at its own pace in the seconds after a cable goes
            // in, so the line rewrote itself two or three times while being
            // read — and rewrote itself into something LONGER, which resized
            // the strip underneath the words.
            //
            // The announcement is confirmation that the cable took. That is all
            // anybody wants at that instant, and it is the one thing already
            // true when it appears. Everything else is a lasting fact and lives
            // in the panel, which is open for as long as somebody wants to know.
            return "Charger connected"
        case .lowBattery(let percent):
            // Says what to do, not just what happened. Low Power Mode is the
            // one action that buys real time, and on a Mac it lives one click
            // away in the panel rather than on the strip, which takes no clicks.
            return percent <= 10
                ? "Battery \(percent)% · plug in soon"
                : "Battery \(percent)% · Low Power Mode helps"
        case .fullyCharged(let percent):
            return percent >= 95 ? "Fully charged" : "Charged to \(percent)%"
        case .unplugged(let percent):
            if let minutes = monitor.minutesRemaining, minutes > 0 {
                return "On battery · \(percent)% · \(Formatters.hoursMinutes(minutes)) left"
            }
            return "On battery · \(percent)%"
        }
    }
}

/// Expanded detail: battery as a clean row that matches the panel, plus the
/// one action worth offering when it is running out.
struct BatteryDetailView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var settings: SettingsStore
    let theme: Theme
    let style: BatteryStyle
    @State private var working = false

    /// When the Low Power Mode line appears: while it is on (so it is never a
    /// mystery why the Mac feels slower), and while the battery is low enough
    /// for it to be the obvious next move. The rest of the time it would just
    /// be another row between the user and the numbers they opened the panel
    /// for.
    private var showsLowPowerRow: Bool {
        monitor.isLowPowerMode || (monitor.state == .discharging && monitor.percentage <= 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotchRow("Battery", theme: theme) {
                HStack(spacing: 6) {
                    if style != .percent, let symbol = stateSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(stateColor)
                    }
                    if let detail = detailText {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                    }
                    // "Icon only" still needs something to read here — a row
                    // labelled Battery with nothing after it is not a readout.
                    // What it drops is the symbol's twin, not the number.
                    if style == .timeRemaining, let minutes = timeFigure {
                        Text(Formatters.hoursMinutes(minutes))
                            .foregroundStyle(monitor.isLowPowerMode ? .yellow : theme.textColor)
                            .monospacedDigit()
                    } else {
                        Text("\(monitor.percentage)%")
                            .foregroundStyle(monitor.isLowPowerMode ? .yellow : theme.textColor)
                            .monospacedDigit()
                            .rollingDigits()
                    }
                }
            }

            if showsLowPowerRow { lowPowerRow }
        }
        .animation(.snappy, value: monitor.percentage)
        .animation(.snappy, value: monitor.isLowPowerMode)
    }

    /// Low Power Mode, by whichever route the user has chosen.
    ///
    /// By default this opens the Battery pane, because macOS offers no public
    /// way to switch the setting and the only thing that can needs root. Turn
    /// on "Switch Low Power Mode from the panel" in Settings and the row
    /// becomes a real toggle that asks macOS for an administrator password each
    /// time — worth it to some people, a nasty surprise to everyone else, which
    /// is why it is opt-in rather than a judgement made on their behalf.
    private var lowPowerRow: some View {
        Button(action: activate) {
            HStack(spacing: 6) {
                Image(systemName: "battery.25")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textColor)
                Spacer(minLength: 6)
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: canSwitchDirectly ? "chevron.right" : "arrow.up.forward")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.subtitleColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.yellow.opacity(monitor.isLowPowerMode ? 0.16 : 0.10))
            )
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(working)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }

    private var canSwitchDirectly: Bool { settings.canSwitchLowPowerMode }

    private var label: String {
        if working { return monitor.isLowPowerMode ? "Turning off…" : "Turning on…" }
        if monitor.isLowPowerMode {
            return canSwitchDirectly ? "Low Power Mode is on — turn off" : "Low Power Mode is on"
        }
        return "Turn on Low Power Mode"
    }

    private func activate() {
        guard canSwitchDirectly else {
            BatteryMonitor.openEnergySettings()
            return
        }
        working = true
        // The monitor is watching the system's own power-state notification, so
        // the new value arrives on its own — there is nothing to write back
        // here, and nothing to get out of step if the password prompt is
        // cancelled or the change is made somewhere else entirely.
        BatteryMonitor.setLowPowerMode(!monitor.isLowPowerMode) { _ in working = false }
    }

    /// Whichever figure of time this state actually has: to full while it
    /// fills, left while it drains, and nothing at all when it is simply full.
    private var timeFigure: Int? {
        monitor.state == .charging ? monitor.minutesToFull : monitor.minutesRemaining
    }

    private var stateSymbol: String? {
        switch monitor.state {
        case .charging: return "bolt.fill"
        case .charged: return "checkmark"
        case .onHold: return "pause.fill"
        case .discharging: return nil
        }
    }

    private var stateColor: Color {
        switch monitor.state {
        case .charging, .charged: return theme.downColor
        case .onHold: return theme.subtitleColor
        case .discharging: return theme.textColor
        }
    }

    private var detailText: String? {
        switch monitor.state {
        case .charging:
            // The two things you actually want while it fills: how long, and
            // whether the adapter to hand is up to the job.
            var parts: [String] = []
            // Count down to the level it is actually going to stop at. On a Mac
            // limited to 80%, "two hours to full" is an answer to a question
            // nobody asked — it will never get there.
            if let ceiling = monitor.chargeCeiling,
               let minutes = BatteryMonitor.minutesToCeiling(
                   minutesToFull: monitor.minutesToFull,
                   percentage: monitor.percentage,
                   ceiling: ceiling
               ) {
                parts.append("\(Formatters.hoursMinutes(minutes)) to \(ceiling)%")
            } else if let minutes = monitor.minutesToFull, minutes > 0 {
                parts.append("\(Formatters.hoursMinutes(minutes)) to full")
            } else {
                // macOS often has no estimate for the first minutes of a
                // charge, and sometimes never — its own menu says "no
                // estimate" in exactly this situation. Saying so is better
                // than a blank space, which reads as the app having failed to
                // notice it is charging at all.
                parts.append("estimating time to full")
            }
            if let watts = monitor.adapterWatts, watts > 0 {
                let speed = monitor.chargeSpeed.map { $0 == .standard ? "" : " \($0.label.lowercased())" } ?? ""
                parts.append("\(watts)W\(speed)")
            }
            return parts.joined(separator: " · ")
        case .charged:
            return nil
        case .onHold:
            // Naming the level turns "why has it stopped at 80%?" into a
            // feature the user already half-knows about — and naming the number
            // is what makes it obviously deliberate rather than broken.
            if let ceiling = monitor.chargeCeiling {
                return "held at \(ceiling)% for battery health"
            }
            return "held for battery health"
        case .discharging:
            guard let minutes = monitor.minutesRemaining, minutes > 0 else { return nil }
            return "\(Formatters.hoursMinutes(minutes)) left"
        }
    }
}
