import Darwin
import Foundation

/// When a process started, asked of the kernel.
///
/// This exists to answer one question the per-program breakdown could not
/// otherwise answer honestly: **is a process this app has not seen before
/// actually new?**
///
/// `nettop` lists the processes with traffic on the links it was asked about,
/// and a process that happens to be quiet at the moment of a sample is simply
/// not in it. The breakdown used to read absence as non-existence — if a
/// process was not in the last sample, it must have started since, and a
/// process's counter starts at zero when the process does, so the whole of its
/// counter was new traffic. That reasoning is sound and the premise is false,
/// and the two together produced a figure that could exceed the total it was a
/// breakdown of: a program running quietly for hours, with a lifetime's traffic
/// on its counter, going busy for one minute had every byte of that lifetime
/// booked into today.
///
/// Measured before it was fixed: over four samples half a minute apart, two
/// processes appeared that were absent from the first — and both had started
/// half an hour before it.
///
/// So the premise is checked rather than assumed. `sysctl` answers for any
/// process this user owns, needs no permission, and costs a few microseconds.
package enum ProcessStart {
    /// When `pid` started, or nil if it cannot be told — which includes a
    /// process that has already exited.
    package static func startedAt(pid: pid_t) -> Date? {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&name, u_int(name.count), &info, &size, nil, 0)
        // A process that has gone answers with a zero-length record rather than
        // an error, so the size has to be checked as well as the return.
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        guard started.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970:
            TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }

    /// The pid on the end of a `nettop` key, or nil if there is not one.
    package static func pid(fromKey key: String) -> pid_t? {
        guard let dot = key.lastIndex(of: "."), dot != key.startIndex else { return nil }
        let digits = key[key.index(after: dot)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return pid_t(digits)
    }

    /// When each process in a reading started.
    package static func startTimes(for keys: some Sequence<String>) -> [String: Date] {
        var times: [String: Date] = [:]
        for key in keys {
            guard let pid = pid(fromKey: key), let started = startedAt(pid: pid) else { continue }
            times[key] = started
        }
        return times
    }
}
