import Foundation
import SwiftUI
import HashNotchKit

/// A file that just finished downloading.
public struct FinishedDownload: Identifiable, Equatable {
    public let id: String        // file name
    public let name: String
    public let at: Date
}

/// Watches the Downloads folder and announces a file the moment its download
/// completes — like the iPhone's "download finished" moment. Browsers write
/// to a temporary part-file (`.crdownload`, `.download`, `.part`) and rename
/// it to the final name when done, so a NEW regular file whose name is not a
/// part-file, appearing while (or just after) a part-file was present, is a
/// completed download. Read-only: it lists names and modification dates,
/// never opens a file.
@MainActor
public final class DownloadsMonitor: ObservableObject {
    @Published public private(set) var latest: FinishedDownload?

    private var watcher: DirectoryWatcher?
    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var known: Set<String> = []
    private var sawPartFile = false
    private var clearWork: DispatchWorkItem?

    private static let partExtensions: Set<String> = ["crdownload", "download", "part", "tmp"]

    private var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence
        // Seed the baseline so pre-existing files never announce on launch.
        known = currentNames()
        sawPartFile = known.contains(where: isPartName)

        // A download finishing IS a change to the folder, so wait to be told
        // instead of re-listing it every couple of seconds forever. A folder
        // nobody is writing to then costs nothing at all to watch.
        watcher = DirectoryWatcher(url: downloadsURL) { [weak self] in self?.scan() }
        if watcher == nil {
            // No Downloads folder, or no permission to watch it. Fall back to
            // the poll rather than quietly never noticing anything again.
            sampler = PollingSampler(interval: 3.0) { [weak self] in self?.scan() }
            sampler?.start()
        }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        sampler?.stop()
        sampler = nil
        clearWork?.cancel()
        clearWork = nil
        latest = nil
        presence?.setActive("downloads", false)
    }

    private func scan() {
        // One directory listing per scan — the part-file check reads the very
        // same names rather than listing the folder a second time.
        let names = currentNames()
        let partPresent = names.contains(where: isPartName)
        // Only treat this as a completed download if a part-file was in flight
        // recently — otherwise a file merely copied in would masquerade as one.
        // A part-file seen in this scan or the previous one counts.
        let wasInFlight = sawPartFile || partPresent

        // New, non-part files that appeared since the last scan.
        let appeared = names.subtracting(known).filter { !isPartName($0) }
        known = names
        sawPartFile = partPresent

        guard wasInFlight, let name = appeared.sorted().last else { return }
        announce(FinishedDownload(id: name, name: name, at: Date()))
    }

    private func announce(_ download: FinishedDownload) {
        guard download != latest else { return }
        latest = download
        presence?.setActive("downloads", true)
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.latest = nil
                self?.presence?.setActive("downloads", false)
            }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: work)
    }

    private func currentNames() -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return Set(contents.map { $0.lastPathComponent })
    }

    /// A name is an in-progress download's temp file. Package-visible so the
    /// checks can pin the extension rule.
    package static func isPartFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return partExtensions.contains(ext)
    }

    private func isPartName(_ name: String) -> Bool { Self.isPartFileName(name) }
}
