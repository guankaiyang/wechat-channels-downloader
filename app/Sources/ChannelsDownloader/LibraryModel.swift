import AppKit
import DownloaderCore
import Foundation

enum LibraryLayout: String, CaseIterable {
    case grid, list
}

/// The videos in the downloads folder, kept up to date as files arrive.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var items: [VideoItem] = []
    @Published var query = ""

    let folder: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init(folder: URL) {
        self.folder = folder
        rescan()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    var visibleItems: [VideoItem] { items.filter { matches($0, query: query) } }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    func rescan() {
        let fresh = scanVideos(in: folder)
        if fresh != items { items = fresh }
        watchFolderIfNeeded()
    }

    /// Instant updates when the folder changes; the 3 s timer covers the folder being created later.
    private func watchFolderIfNeeded() {
        guard watcher == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if source.data.contains(.delete) || source.data.contains(.rename) {
                    self.watcher?.cancel()
                    self.watcher = nil
                }
                self.rescan()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: Actions

    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func play(_ item: VideoItem) {
        let quickTime = URL(fileURLWithPath: "/System/Applications/QuickTime Player.app")
        if FileManager.default.fileExists(atPath: quickTime.path) {
            NSWorkspace.shared.open([item.url], withApplicationAt: quickTime,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func reveal(_ item: VideoItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func rename(_ item: VideoItem, to title: String) throws {
        _ = try renameVideo(item, to: title)
        rescan()
    }

    func moveToTrash(_ item: VideoItem) throws {
        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        rescan()
    }
}
