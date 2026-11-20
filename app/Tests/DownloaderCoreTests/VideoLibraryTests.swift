import Foundation
import Testing
@testable import DownloaderCore

private func touch(_ dir: URL, _ name: String, bytes: Int = 10, age: TimeInterval = 0) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 7, count: bytes).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    return url
}

private func item(_ url: URL) throws -> VideoItem {
    try #require(scanVideos(in: url.deletingLastPathComponent()).first { $0.url.lastPathComponent == url.lastPathComponent })
}

@Suite struct VideoLibraryTests {
    @Test func scanFiltersAndSorts() throws {
        let dir = try makeTempDir()
        _ = try touch(dir, "old.mp4", age: 60)
        _ = try touch(dir, "new.MOV")
        _ = try touch(dir, "clip.mp4.part")
        _ = try touch(dir, "seg.tmp")
        _ = try touch(dir, ".hidden.mp4")
        _ = try touch(dir, "notes.txt")
        _ = try touch(dir, "sub/x.mp4")
        let titles = scanVideos(in: dir).map(\.title)
        #expect(titles == ["new", "old"])
    }

    @Test func scanReportsSizeAndDate() throws {
        let dir = try makeTempDir()
        _ = try touch(dir, "a.m4v", bytes: 1234, age: 3600)
        let found = try #require(scanVideos(in: dir).first)
        #expect(found.sizeBytes == 1234)
        #expect(abs(found.modified.timeIntervalSinceNow + 3600) < 5)
    }

    @Test func scanMissingDirReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(scanVideos(in: missing).isEmpty)
    }

    @Test func searchIsCaseInsensitiveAndHandlesChinese() throws {
        let dir = try makeTempDir()
        let video = try item(try touch(dir, "春节 Vlog.mp4"))
        #expect(matches(video, query: "vlog"))
        #expect(matches(video, query: "春节"))
        #expect(matches(video, query: "  VLOG "))
        #expect(!matches(video, query: "xyz"))
        #expect(matches(video, query: ""))
    }

    @Test func durationFormatting() {
        #expect(formatDuration(5) == "0:05")
        #expect(formatDuration(92) == "1:32")
        #expect(formatDuration(3723) == "1:02:03")
    }

    @Test func renameKeepsExtension() throws {
        let dir = try makeTempDir()
        let original = try item(try touch(dir, "a.mp4"))
        let renamed = try renameVideo(original, to: "b")
        #expect(renamed.lastPathComponent == "b.mp4")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
    }

    @Test func renameRejectsExisting() throws {
        let dir = try makeTempDir()
        let a = try item(try touch(dir, "a.mp4", bytes: 1))
        _ = try touch(dir, "b.mp4", bytes: 2)
        #expect(throws: RenameError.alreadyExists) { try renameVideo(a, to: "b") }
        #expect(FileManager.default.fileExists(atPath: a.url.path))
        let b = try Data(contentsOf: dir.appendingPathComponent("b.mp4"))
        #expect(b.count == 2)
    }

    @Test func renameRejectsSlashAndEmpty() throws {
        let dir = try makeTempDir()
        let a = try item(try touch(dir, "a.mp4"))
        #expect(throws: RenameError.invalidCharacters) { try renameVideo(a, to: "a/b") }
        #expect(throws: RenameError.invalidCharacters) { try renameVideo(a, to: "a:b") }
        #expect(throws: RenameError.empty) { try renameVideo(a, to: "   ") }
        #expect(FileManager.default.fileExists(atPath: a.url.path))
    }

    @Test func cacheKeyChangesWithSizeOrDate() {
        let url = URL(fileURLWithPath: "/v/a.mp4")
        let base = VideoItem(url: url, title: "a", sizeBytes: 10, modified: Date(timeIntervalSince1970: 100))
        var bigger = base; bigger.sizeBytes = 20
        var newer = base; newer.modified = Date(timeIntervalSince1970: 200)
        #expect(ThumbnailKey(base) == ThumbnailKey(base))
        #expect(ThumbnailKey(base) != ThumbnailKey(bigger))
        #expect(ThumbnailKey(base) != ThumbnailKey(newer))
    }
}

@Suite struct SelectionTests {
    @Test func menuTargetNeedsExactlyOneSelection() {
        let a = VideoItem(url: URL(fileURLWithPath: "/v/a.mp4"), title: "a", sizeBytes: 1, modified: .now)
        let b = VideoItem(url: URL(fileURLWithPath: "/v/b.mp4"), title: "b", sizeBytes: 1, modified: .now)
        #expect(singleItem(for: [a.url], in: [a, b]) == a)
        #expect(singleItem(for: [a.url, b.url], in: [a, b]) == nil)
        #expect(singleItem(for: [], in: [a, b]) == nil)
        #expect(singleItem(for: [URL(fileURLWithPath: "/v/gone.mp4")], in: [a, b]) == nil)
    }
}
