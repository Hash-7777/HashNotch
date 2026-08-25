import Foundation
import Darwin

/// Reads real on-die temperature sensors on Apple Silicon via the IOKit HID
/// event system (`IOHIDEventSystemClient`). These symbols are not in the public
/// SDK headers, so they are resolved at runtime with `dlsym`; if anything is
/// missing the reader simply returns no sensors and the feature falls back to
/// the coarse thermal-pressure label.
///
/// This is a private-API path (fine for a local / open-source app, not for the
/// Mac App Store). Sensor availability and naming vary by chip, so treat the
/// values as indicative and verify on the target Mac.
/// Confined to `ThermalMonitor`'s own serial queue, which is the only thing that
/// ever touches it — the client handle is a raw pointer held outside ARC's view
/// and must not be used from two threads at once.
final class AppleSiliconThermal: @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer?) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer?, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Double

    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let client: UnsafeMutableRawPointer

    // kIOHIDEventTypeTemperature = 15; the field is the type shifted into the
    // high word (IOHIDEventFieldBase).
    private let temperatureType: Int64 = 15
    private var temperatureField: Int32 { Int32(temperatureType << 16) }

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return nil
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        guard let create = symbol("IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloatFn.self),
              let client = create(kCFAllocatorDefault)
        else {
            return nil
        }

        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat
        self.client = client

        // Match Apple's temperature-sensor HID usage (page 0xFF00, usage 5).
        let matching: [String: Int] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 5,
        ]
        setMatching(client, matching as CFDictionary)
    }

    deinit {
        // We own the client (+1 from Create); balance it manually since it is
        // held as a raw pointer outside ARC's view.
        Unmanaged<AnyObject>.fromOpaque(client).release()
    }

    /// One reading per available temperature sensor, in °C.
    func read() -> [(name: String, celsius: Double)] {
        guard let services = copyServices(client)?.takeRetainedValue() else { return [] }

        var results: [(name: String, celsius: Double)] = []
        let count = CFArrayGetCount(services)

        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)

            guard let event = copyEvent(service, temperatureType, 0, 0) else { continue }
            let celsius = getFloat(event, temperatureField)
            // We own the event (+1 from Copy); release it as a raw pointer.
            Unmanaged<AnyObject>.fromOpaque(event).release()

            guard celsius.isFinite, celsius > 0, celsius < 130 else { continue }

            var name = "Sensor \(index)"
            // The type is checked and then the cast is asked rather than
            // forced. The check above makes the force safe today; it makes it
            // safe only as long as the two lines stay together, and the cost of
            // asking is nothing at all.
            if let property = copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
               CFGetTypeID(property) == CFStringGetTypeID(),
               let product = property as? String {
                name = product
            }

            results.append((name, celsius))
        }

        return results
    }
}
