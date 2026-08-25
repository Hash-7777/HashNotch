import Foundation
import IOKit

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
    // MARK: The SMC's own request block
    //
    // The layout has to match the kernel's byte for byte. It is easy to get
    // wrong in a way that looks like the hardware refusing you: an early
    // version of this was three bytes short, because C places the field after a
    // struct at its STRIDE and Swift places it at its SIZE, and the SMC
    // answered every call with a bad-argument error.

    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct Limits {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    /// Nine bytes of fields in a four-aligned struct, which C pads to twelve.
    /// The padding is spelled out because Swift will not add it.
    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0
    }

    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var limits = Limits()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    /// The three commands used, and the one selector they go through.
    private static let selector: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readIndex: UInt8 = 8
    private static let readKeyInfo: UInt8 = 9

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

    private let connection: io_connect_t
    /// Discovered once. Each read then costs one call per key rather than
    /// three, because what the key is and how big it is cannot change.
    private var sensors: [(key: UInt32, name: String, info: KeyInfo)] = []

    package init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard opened == kIOReturnSuccess, connection != 0 else { return nil }
        self.connection = connection
        discover()
        if sensors.isEmpty {
            IOServiceClose(connection)
            return nil
        }
    }

    deinit { IOServiceClose(connection) }

    /// Every temperature this Mac reports, by its raw key.
    package func read() -> [(name: String, celsius: Double)] {
        var results: [(String, Double)] = []
        results.reserveCapacity(sensors.count)
        for sensor in sensors {
            var request = Param()
            request.key = sensor.key
            request.keyInfo = sensor.info
            request.data8 = Self.readBytes
            guard let answer = call(&request) else { continue }
            guard let celsius = Self.celsius(
                type: Self.text(fromKey: sensor.info.dataType),
                size: sensor.info.dataSize,
                bytes: Self.array(answer.bytes)
            ) else { continue }
            results.append((sensor.name, celsius))
        }
        return results
    }

    // MARK: Discovery

    private func discover() {
        guard let total = keyCount(), total > 0 else { return }
        for index in 0..<min(Int(total), Self.keyCeiling) {
            var byIndex = Param()
            byIndex.data8 = Self.readIndex
            byIndex.data32 = UInt32(index)
            guard let named = call(&byIndex) else { continue }
            let name = Self.text(fromKey: named.key)
            // Temperatures only. Every other key on the SMC is a fan, a
            // voltage, a current or something this app has no business reading.
            guard name.hasPrefix("T") else { continue }

            var info = Param()
            info.key = named.key
            info.data8 = Self.readKeyInfo
            guard let described = call(&info) else { continue }

            // A key is kept only if it answers with a plausible temperature
            // right now. That is what keeps the list to sensors that exist and
            // work on THIS Mac, rather than to a list of names off another one.
            var value = Param()
            value.key = named.key
            value.keyInfo = described.keyInfo
            value.data8 = Self.readBytes
            guard let answer = call(&value),
                  Self.celsius(
                    type: Self.text(fromKey: described.keyInfo.dataType),
                    size: described.keyInfo.dataSize,
                    bytes: Self.array(answer.bytes)) != nil
            else { continue }

            sensors.append((named.key, name, described.keyInfo))
            if sensors.count >= Self.sensorLimit { return }
        }
    }

    private func keyCount() -> UInt32? {
        var request = Param()
        request.key = Self.key(fromText: "#KEY")
        request.data8 = Self.readKeyInfo
        guard let described = call(&request) else { return nil }
        request.keyInfo = described.keyInfo
        request.data8 = Self.readBytes
        guard let answer = call(&request) else { return nil }
        let bytes = Self.array(answer.bytes)
        guard bytes.count >= 4 else { return nil }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
             | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.selector, &input, MemoryLayout<Param>.stride, &output, &size)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
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
        let bytes = [UInt8((key >> 24) & 0xff), UInt8((key >> 16) & 0xff),
                     UInt8((key >> 8) & 0xff), UInt8(key & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }

    package static func key(fromText text: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in text.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private static func array(
        _ bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    ) -> [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }
}
