import Foundation
import Darwin
import HashNotchKit

/// Reads live upload/download throughput by diffing the kernel's per-interface
/// byte counters (getifaddrs / if_data) once a second. Public API only.
@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var uploadBytesPerSec: Double = 0
    @Published public private(set) var downloadBytesPerSec: Double = 0
    /// Recent rates, oldest first, for the graph styles.
    @Published public private(set) var upHistory: [Double] = []
    @Published public private(set) var downHistory: [Double] = []

    /// Half a minute of samples. Held here rather than in the view so the shape
    /// survives a redraw.
    private static let historyLength = 30

    /// What the graphs are drawn against: the busiest moment still in view, or
    /// a floor of 1 MB/s — otherwise an idle link has its own noise magnified
    /// to fill the frame and looks like a storm.
    public var graphCeiling: Double {
        max(1_000_000, (upHistory + downHistory).max() ?? 0)
    }

    private static let interval: TimeInterval = 1.0
    /// The interval actually in use, which battery saver stretches. The
    /// staleness rule is measured against this rather than the nominal value,
    /// so a saver-paced reading is not mistaken for an ancient one.
    private var effectiveInterval: TimeInterval = interval

    private var sampler: VisibleSampler?
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastTime: TimeInterval = 0

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double = 1) {
        let counters = Self.counters()
        lastRx = counters.rx
        lastTx = counters.tx
        lastTime = Date().timeIntervalSinceReferenceDate
        effectiveInterval = Self.interval * scale
        // Throughput is only ever drawn in the panel, so it is measured only
        // while the panel is open.
        sampler = VisibleSampler(interval: effectiveInterval, visibility: visibility) { [weak self] in
            self?.sample()
        }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    /// Whether the previous reading is too old to diff against.
    ///
    /// Throughput is a difference over time, so it is only meaningful between
    /// two readings taken a moment apart. After the panel has been shut — or
    /// the Mac asleep — the last reading can be hours old, and diffing against
    /// it would report an average over that whole period as if it were the
    /// speed right now. Such a reading is thrown away and used as the new
    /// baseline instead, costing one interval before the first number appears.
    ///
    /// Pure and package-visible so the checks can pin it.
    package nonisolated static func isStaleBaseline(
        dt: TimeInterval,
        interval: TimeInterval
    ) -> Bool {
        dt > interval * 3
    }

    private func sample() {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = max(0.001, now - lastTime)
        let counters = Self.counters()

        guard !Self.isStaleBaseline(dt: dt, interval: effectiveInterval) else {
            lastRx = counters.rx
            lastTx = counters.tx
            lastTime = now
            return
        }

        // Counters can wrap (32-bit) or reset; treat a decrease as zero delta.
        let dRx = counters.rx >= lastRx ? counters.rx - lastRx : 0
        let dTx = counters.tx >= lastTx ? counters.tx - lastTx : 0

        let newDownload = Double(dRx) / dt
        let newUpload = Double(dTx) / dt

        // Only publish when the displayed MB/s value actually changes, so an idle
        // link (0.00) triggers no SwiftUI redraws at all.
        if Formatters.megabytesPerSecond(newDownload) != Formatters.megabytesPerSecond(downloadBytesPerSec) {
            downloadBytesPerSec = newDownload
        }
        if Formatters.megabytesPerSecond(newUpload) != Formatters.megabytesPerSecond(uploadBytesPerSec) {
            uploadBytesPerSec = newUpload
        }

        // The history takes every sample, including the ones too small to
        // change the printed number — a graph of only the changes would be a
        // graph with the quiet parts cut out.
        upHistory.append(newUpload)
        downHistory.append(newDownload)
        if upHistory.count > Self.historyLength {
            upHistory.removeFirst(upHistory.count - Self.historyLength)
            downHistory.removeFirst(downHistory.count - Self.historyLength)
        }

        lastRx = counters.rx
        lastTx = counters.tx
        lastTime = now
    }

    /// Sum of received/sent bytes across all non-loopback link-layer interfaces.
    private static func counters() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let sockaddr = interface.ifa_addr,
               sockaddr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if !name.hasPrefix("lo"), let data = interface.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(stats.ifi_ibytes)
                    tx += UInt64(stats.ifi_obytes)
                }
            }
            cursor = interface.ifa_next
        }
        return (rx, tx)
    }
}
