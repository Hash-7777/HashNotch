import Foundation

/// Small local snapshots written by desktop apps. This reader never modifies them.
public enum LocalActivityFeed {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Local Activity Feed", isDirectory: true)
    }

    public static func read(_ url: URL, maxBytes: Int) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= maxBytes,
              let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes
        else { return nil }
        return data
    }

    public static func files(in directory: URL, suffix: String, maxBytes: Int) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }
        var found: [(URL, Date)] = []
        for entry in entries.prefix(128) {
            guard let url = entry as? URL, url.lastPathComponent.hasSuffix(suffix),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink == false,
                  let size = values.fileSize, size > 0, size <= maxBytes else { continue }
            found.append((url, values.contentModificationDate ?? .distantPast))
        }
        return found.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
            .prefix(32).map(\.0)
    }
}
