import Foundation

/// Calls back when the contents of a directory change.
///
/// This replaces re-listing a folder on a timer. A folder that nothing writes
/// to costs exactly nothing to watch, where a poll pays the same price every
/// few seconds forever to discover that nothing happened.
///
/// The directory is watched rather than a single file on purpose: a file
/// written atomically is replaced by a rename, which destroys the descriptor a
/// file-level watch is holding, and the watch would go permanently deaf after
/// the first update.
///
/// Changes are coalesced — a writer can produce several events for one logical
/// update — and a directory that does not exist yet is simply not watched, so
/// the caller keeps whatever fallback it has.
@MainActor
public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let onChange: () -> Void
    private let coalesce: TimeInterval
    private var pending: DispatchWorkItem?

    /// Returns nil when the directory cannot be opened — a missing folder, or
    /// one we are not allowed to read.
    public init?(url: URL, coalesce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.coalesce = coalesce

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleCallback() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        self.source = source
        source.resume()
    }

    private func scheduleCallback() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesce, execute: work)
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
