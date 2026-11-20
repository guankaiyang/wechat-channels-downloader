import Foundation

public let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

public struct VideoItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public var url: URL
    public var title: String
    public var sizeBytes: Int64
    public var modified: Date

    public init(url: URL, title: String, sizeBytes: Int64, modified: Date) {
        self.url = url
        self.title = title
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

/// Finished videos directly inside `dir`, newest first. Unfinished downloads (.part/.tmp) are skipped.
public func scanVideos(in dir: URL, fileManager: FileManager = .default) -> [VideoItem] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard let urls = try? fileManager.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
    let items: [VideoItem] = urls.compactMap { url in
        guard videoExtensions.contains(url.pathExtension.lowercased()),
              let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isRegularFile == true else { return nil }
        return VideoItem(url: url,
                         title: displayTitle(for: url),
                         sizeBytes: Int64(values.fileSize ?? 0),
                         modified: values.contentModificationDate ?? .distantPast)
    }
    return items.sorted { $0.modified > $1.modified }
}

public func displayTitle(for url: URL) -> String {
    url.deletingPathExtension().lastPathComponent
}

public func matches(_ item: VideoItem, query: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return true }
    return item.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}

public func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

public func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

public enum RenameError: Error, Equatable {
    case empty, invalidCharacters, alreadyExists

    public var message: String {
        switch self {
        case .empty: return "Please enter a name."
        case .invalidCharacters: return "Names can't contain “/” or “:”."
        case .alreadyExists: return "A video with that name already exists."
        }
    }
}

/// Renames a video in place, keeping its extension. Never overwrites another file.
public func renameVideo(_ item: VideoItem, to newTitle: String,
                        fileManager: FileManager = .default) throws -> URL {
    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw RenameError.empty }
    guard !title.contains("/"), !title.contains(":") else { throw RenameError.invalidCharacters }
    let target = item.url.deletingLastPathComponent()
        .appendingPathComponent(title)
        .appendingPathExtension(item.url.pathExtension)
    guard !fileManager.fileExists(atPath: target.path) else { throw RenameError.alreadyExists }
    try fileManager.moveItem(at: item.url, to: target)
    return target
}

/// Identifies one version of a file, so thumbnails refresh when a download is rewritten.
public struct ThumbnailKey: Hashable, Sendable {
    public let url: URL
    public let sizeBytes: Int64
    public let modified: Date

    public init(_ item: VideoItem) {
        url = item.url
        sizeBytes = item.sizeBytes
        modified = item.modified
    }
}

/// The one video a menu should act on, or nil unless exactly one known video is selected.
public func singleItem(for ids: Set<URL>, in items: [VideoItem]) -> VideoItem? {
    guard ids.count == 1, let id = ids.first else { return nil }
    return items.first { $0.url == id }
}
