import Foundation
import IOKit
import HashNotchKit

/// Reads temperatures from the System Management Controller.
///
/// **Why this exists alongside the other reader.** `AppleSiliconThermal` asks
/// the HID event system, which gives well-named sensors — but only on Apple
/// Silicon. On an Intel Mac it resolves nothing and the panel falls back to the
/// coarse pressure word, so those machines never saw a temperature at all. The
/// SMC is the one interface every Mac has had for as long as there have been
/// Intel Macs, and it is still there on Apple Silicon.
///
/// So this is the floor: the other reader is tried first because its names are
/// better, and this answers when it cannot.
///
/// **Nothing here is guessed at.** The keys are discovered by asking the SMC
/// how many it has and walking them, rather than from a list of key names
/// collected from some particular model — which is what makes it work on a Mac
/// nobody has tried it on. On the machine this was written on it finds 1,631
/// keys, 116 of which are temperatures with a plausible reading.
///
/// Confined to whatever queue owns it — a Mach connection is not safe to use
/// from two threads at once, and `ThermalMonitor` has a serial queue for exactly
/// this.
package final class SMCThermal: @unchecked Sendable {
    /// How many keys are walked at most while discovering.
    ///
    /// A ceiling rather than a limit: this Mac reports about sixteen hundred,
    /// and a number far past that means something has answered nonsense — which
    /// should end the loop rather than run it forever.
    private static let keyCeiling = 8_192

    /// How many temperature sensors are kept.
    ///
    /// They fold into a handful of named rows, so reading a hundred of them
    /// every sample is work with no answer attached. The hottest few per part of
    /// the machine is the whole of what the panel shows.
    package static let sensorLimit = 48

    /// The request plumbing lives in the core (`SMCConnection`), because this
    /// is not the only feature that reads the SMC.
    private let smc: SMCConnection
    /// Discovered once. Each read then costs one call per key rather than
    /// three, because what the key is and how big it is cannot change.
    private var sensors: [(key: UInt32, name: String, info: SMCConnection.KeyInfo)] = []

    package init?() {
        guard let smc = SMCConnection() else { return nil }
        self.smc = smc
        discover()
        if sensors.isEmpty { return nil }
    }

    /// Every temperature this Mac reports, by its raw key.
    package func read() -> [(name: String, celsius: Double)] {
        var results: [(String, Double)] = []
        results.reserveCapacity(sensors.count)
        for sensor in sensors {
            guard let bytes = smc.bytes(for: sensor.key, info: sensor.info),
                  let celsius = Self.celsius(
                    type: sensor.info.type, size: sensor.info.dataSize, bytes: bytes)
            else { continue }
            results.append((sensor.name, celsius))
        }
        return results
    }

    // MARK: Discovery

    private func discover() {
        guard let total = smc.keyCount(), total > 0 else { return }
        for index in 0..<min(Int(total), Self.keyCeiling) {
            guard let key = smc.key(at: UInt32(index)) else { continue }
            let name = Self.text(fromKey: key)
            // Temperatures only. Every other key on the SMC is a fan, a
            // voltage, a current or something this app has no business reading.
            guard name.hasPrefix("T") else { continue }

            guard let described = smc.info(for: key) else { continue }

            // A key is kept only if it answers with a plausible temperature
            // right now. That is what keeps the list to sensors that exist and
            // work on THIS Mac, rather than to a list of names off another one.
            guard let bytes = smc.bytes(for: key, info: described),
                  Self.celsius(type: described.type, size: described.dataSize, bytes: bytes) != nil
            else { continue }

            sensors.append((key, name, described))
            if sensors.count >= Self.sensorLimit { return }
        }
    }

    // MARK: Plain arithmetic, so the checks can reach it

    /// A reading, or nil for a key whose type this does not understand or whose
    /// value is not a temperature a Mac could be at.
    ///
    /// The two types that matter are the SMC's own fixed-point form and an
    /// ordinary float. Anything else is left alone rather than guessed at: a
    /// wrong temperature is worse than a missing one.
    package static func celsius(type: String, size: UInt32, bytes: [UInt8]) -> Double? {
        var value: Double?
        if type == "sp78", size == 2, bytes.count >= 2 {
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            value = Double(raw) / 256
        } else if type == "flt ", size == 4, bytes.count >= 4 {
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                    | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            value = Double(Float(bitPattern: raw))
        }
        guard let value, value.isFinite, value > 0, value < 130 else { return nil }
        return value
    }

    /// The four characters of a key, which is how the SMC names everything.
    package static func text(fromKey key: UInt32) -> String {
        SMCConnection.text(fromKey: key)
    }

    package static func key(fromText text: String) -> UInt32 {
        SMCConnection.key(fromText: text)
    }
}
