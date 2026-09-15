import Foundation
import IOKit
import IOKit.ps
import HashNotchKit

/// How much power the whole Mac is drawing right now, whether it is coming from
/// the charger or from the battery.
///
/// Three sources, tried in order, all read-only and none needing a permission:
///
/// 1. The System Management Controller's system total, key `PSTR`, in watts.
///    It refreshes every second and is what makes the figure "right now".
///    Measured against the battery controller on an M2 MacBook Air: equal to a
///    few hundredths of a watt whenever both were fresh.
/// 2. The battery controller's telemetry — `AppleSmartBattery` in the I/O
///    Registry, where `ioreg` shows it — whose `SystemLoad` is the same total
///    in milliwatts. The same number, but refreshed only every twenty seconds
///    or so, which is why it is second.
/// 3. The battery's own voltage and current, while it is running down: the one
///    moment they describe the whole machine.
///
/// None of them is what the charger delivers or what the battery gives up: it
/// is what the Mac as a whole is using, so the figure means the same thing on
/// either. When none answers, no figure is shown rather than a guessed one.
package enum PowerReader {
    /// A draw beyond this is a misread, not a Mac. Registry values are unsigned
    /// and a negative one arrives as a number in the quintillions.
    package static let plausibleCeilingWatts = 1_000.0

    /// The whole Mac's draw in watts: the SMC's system total when it gives a
    /// plausible one, else the controller's telemetry, else the battery's own
    /// voltage (millivolts) and current (milliamps) while it is running down.
    /// Nil when none answers.
    package static func watts(
        smcSystemTotal: Double? = nil,
        telemetry: [String: Any]?,
        batteryMillivolts: Int64?,
        batteryMilliamps: Int64?
    ) -> Double? {
        if let total = smcSystemTotal, total.isFinite, total > 0, total < plausibleCeilingWatts {
            return total
        }
        if let load = (telemetry?["SystemLoad"] as? NSNumber)?.int64Value, load > 0 {
            let watts = Double(load) / 1_000
            return watts < plausibleCeilingWatts ? watts : nil
        }
        // Current is negative while the battery is discharging. Positive is
        // charging, when the battery is a load on the charger rather than the
        // source of the whole Mac's power, so it describes nothing here.
        guard let millivolts = batteryMillivolts, let milliamps = batteryMilliamps,
              millivolts > 0, milliamps < 0 else { return nil }
        let watts = Double(millivolts) * Double(-milliamps) / 1_000_000
        return watts < plausibleCeilingWatts ? watts : nil
    }

    /// The connected charger's rating in watts, or nil on battery or when the
    /// charger does not say.
    static func chargerWatts() -> Double? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 else { return nil }
        return Double(watts)
    }

    /// The battery controller, or 0 on a Mac without one. The caller releases
    /// it with `IOObjectRelease`.
    static func batteryService() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    /// One reading. `service` is the controller found by `batteryService()`,
    /// or 0 on a Mac without one; only the three properties the figure is made
    /// from are asked for, rather than the controller's whole dictionary, which
    /// carries history arrays nobody here needs — and only when the SMC did not
    /// answer first.
    static func read(smc: SMCConnection?, battery service: io_service_t) -> Double? {
        if let total = smc?.float("PSTR"),
           let watts = watts(smcSystemTotal: total, telemetry: nil, batteryMillivolts: nil, batteryMilliamps: nil) {
            return watts
        }
        guard service != 0 else { return nil }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }
        return watts(
            telemetry: property("PowerTelemetryData") as? [String: Any],
            batteryMillivolts: (property("Voltage") as? NSNumber)?.int64Value,
            batteryMilliamps: (property("InstantAmperage") as? NSNumber)?.int64Value
        )
    }
}

/// When the power reading turns red.
///
/// Power has no fixed "100%", but a charger does: it can deliver so many watts
/// and no more. At 90% of that — the same share every other readout turns red
/// at — the Mac is close to asking for more than the charger gives, and the
/// battery starts making up the difference while plugged in. On battery there
/// is no such limit, so the reading stays in the accent.
package enum PowerLevel {
    package static func level(watts: Double, chargerWatts: Double?) -> ReadingLevel {
        guard let chargerWatts, chargerWatts > 0 else { return .normal }
        return .of(share: watts / chargerWatts)
    }
}

/// How a draw is written: a decimal below a hundred watts, where the tenth is
/// a real difference on a laptop, and whole watts above it.
package enum PowerFormat {
    package static func watts(_ value: Double) -> String {
        value < 100 ? String(format: "%.1f W", value) : String(format: "%.0f W", value)
    }
}
