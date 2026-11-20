import AppKit
import AppViews
import Testing

@MainActor
@Suite struct FileDragTests {
    @Test func dragSourceOnlyOffersCopy() {
        // Copy only: a drop on Finder (even on the same disk) must never move the video out of the library.
        let outside = FileDragSource.operationMask(for: .outsideApplication)
        #expect(outside == .copy)
        // Nothing inside the app accepts these drops (e.g. the search field must not get a file path).
        #expect(FileDragSource.operationMask(for: .withinApplication) == [])
    }

    @Test func dragItemsCarryFileURLs() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a video.mp4"), URL(fileURLWithPath: "/tmp/b.mov")]
        let items = fileDragItems(for: urls, at: NSPoint(x: 100, y: 100))
        #expect(items.count == 2)
        for (item, url) in zip(items, urls) {
            let written = try #require(item.item as? NSURL)
            #expect(written.isFileURL)
            #expect(written as URL == url)
            #expect(item.draggingFrame.width > 0 && item.draggingFrame.height > 0)
        }
    }
}
