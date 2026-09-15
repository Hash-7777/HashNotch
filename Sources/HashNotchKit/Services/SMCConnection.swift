import Foundation
import IOKit

/// A connection to the System Management Controller, and the one request it
/// understands.
///
/// Here in the core rather than inside a feature because more than one feature
/// reads the SMC — temperatures, and the whole machine's power draw — and a
/// feature may not depend on another. The request block's layout is the part
/// that is easy to get wrong, so there is one copy of it.
///
/// Read-only throughout: the three commands used ask what a key is, which key
/// sits at an index, and what a key currently holds. Nothing here writes to the
/// SMC.
///
/// Confined to whatever thread or queue owns it — a Mach connection is not safe
/// to use from two at once.
package final class SMCConnection: @unchecked Sendable {
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
    package struct KeyInfo: Sendable {
        package var dataSize: UInt32 = 0
        package var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0

        /// The key's type, as the SMC's four characters — "flt ", "sp78", …
        package var type: String { SMCConnection.text(fromKey: dataType) }
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

    private let connection: io_connect_t

    /// Nil on a machine with no SMC, or one that will not open a connection.
    package init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard opened == kIOReturnSuccess, connection != 0 else { return nil }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    // MARK: The three questions

    /// What a key is — its type and size — or nil for a key this SMC lacks.
    package func info(for key: UInt32) -> KeyInfo? {
        var request = Param()
        request.key = key
        request.data8 = Self.readKeyInfo
        return call(&request)?.keyInfo
    }

    /// Which key sits at a position in the SMC's own list.
    package func key(at index: UInt32) -> UInt32? {
        var request = Param()
        request.data8 = Self.readIndex
        request.data32 = index
        return call(&request)?.key
    }

    /// What a key currently holds, as the SMC's raw bytes.
    package func bytes(for key: UInt32, info: KeyInfo) -> [UInt8]? {
        var request = Param()
        request.key = key
        request.keyInfo = info
        request.data8 = Self.readBytes
        guard let answer = call(&request) else { return nil }
        return withUnsafeBytes(of: answer.bytes) { Array($0) }
    }

    /// How many keys this SMC has.
    package func keyCount() -> UInt32? {
        let count = Self.key(fromText: "#KEY")
        guard let described = info(for: count),
              let bytes = bytes(for: count, info: described), bytes.count >= 4 else { return nil }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
             | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    /// An ordinary float key's value, or nil when the key is missing or is not
    /// a float.
    package func float(_ name: String) -> Double? {
        let key = Self.key(fromText: name)
        guard let described = info(for: key), described.type == "flt ", described.dataSize == 4,
              let bytes = bytes(for: key, info: described) else { return nil }
        return Self.float(fromLittleEndian: bytes)
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

    /// A "flt " value: four bytes, least significant first.
    package static func float(fromLittleEndian bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: raw))
        return value.isFinite ? value : nil
    }
}
