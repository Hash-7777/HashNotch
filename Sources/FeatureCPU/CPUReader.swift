import Darwin
import Foundation

/// How busy the processor is, as a fraction from 0 to 1.
///
/// The kernel counts TICKS spent in each state since boot, not a percentage —
/// so a single reading says nothing at all. Usage is the difference between two
/// readings: the busy ticks that accrued between them over all the ticks that
/// did. That is why the first sample after starting reports nothing rather than
/// a number, and why a number taken hours apart would describe the average
/// since boot instead of what the machine is doing now.
package struct CPUTicks: Equatable {
    package let busy: UInt64
    package let idle: UInt64

    package init(busy: UInt64, idle: UInt64) {
        self.busy = busy
        self.idle = idle
    }

    package var total: UInt64 { busy &+ idle }

    /// The load between this reading and a later one. Nil when the counters did
    /// not move, or moved backwards — which they do when they wrap.
    package func load(to later: CPUTicks) -> Double? {
        let busyDelta = later.busy &- busy
        let totalDelta = later.total &- total
        guard later.total >= total, later.busy >= busy, totalDelta > 0 else { return nil }
        return min(1, max(0, Double(busyDelta) / Double(totalDelta)))
    }
}

/// Reads the kernel's own processor tick counters. Public API, no permission,
/// and about as cheap as a reading gets — one call, no subprocess, no file.
package enum CPUReader {
    package static func ticks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // User, system and nice are all the machine doing something for
        // somebody. Only idle is not.
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user &+ system &+ nice, idle: idle)
    }
}

/// Load from one reading to the next, for a reader that keeps its own clock.
///
/// Only ever used on the one queue that reads it, which is what makes it safe
/// to hand across: it is never touched from two threads, so there is nothing
/// for a lock to protect.
package final class CPULoadTracker: @unchecked Sendable {
    private var previous: CPUTicks?
    private let read: () -> CPUTicks?

    package init(read: @escaping () -> CPUTicks? = CPUReader.ticks) {
        self.read = read
    }

    /// The load since the last call. Nil on the first, which has nothing to
    /// compare with — the same rule as the panel's monitor.
    package func next() -> Double? {
        guard let now = read() else { return nil }
        defer { previous = now }
        guard let previous else { return nil }
        return previous.load(to: now)
    }
}
