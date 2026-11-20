import Foundation
import IOKit

/// How busy the graphics processor is, as a fraction from 0 to 1.
///
/// The graphics driver keeps its own running figures in the I/O Registry, under
/// each accelerator's `PerformanceStatistics`, and one of them is how much of
/// the time the processor was doing work. It is a level rather than a counter,
/// so one reading is already an answer — unlike the processor, which needs two
/// readings a second apart before it can say anything.
///
/// Reading it is public IOKit, needs no permission and starts no subprocess.
/// The key's name is not something Apple documents, so a Mac whose driver does
/// not publish it gets no figure at all, and the panel says so, rather than a
/// zero that looks like an idle graphics processor.
package enum GPUReader {
    /// Where the driver keeps its figures, and the one figure read from them.
    package static let statisticsKey = "PerformanceStatistics"
    package static let utilizationKey = "Device Utilization %"

    /// The share from one accelerator's statistics, or nil when it does not
    /// carry one — or carries something that is not a percentage.
    package static func share(from statistics: [String: Any]) -> Double? {
        guard let number = statistics[utilizationKey] as? NSNumber else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, percent >= 0 else { return nil }
        return min(1, percent / 100)
    }

    /// One figure from every accelerator this Mac reports: the busiest.
    ///
    /// Apple Silicon has one. A Mac with a second, switchable graphics
    /// processor has two, and the one that is idle says nothing about how hard
    /// the other is working — so the busier one is the answer, not an average
    /// that halves it.
    package static func combined(_ shares: [Double?]) -> Double? {
        shares.compactMap { $0 }.max()
    }

    /// Ask the registry. About as cheap as a reading gets: one lookup per
    /// accelerator, no file and no subprocess.
    package static func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var shares: [Double?] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            guard let value = IORegistryEntryCreateCFProperty(
                entry, statisticsKey as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
                let statistics = value as? [String: Any]
            else { continue }
            shares.append(share(from: statistics))
        }
        return combined(shares)
    }
}
