import AppKit
import SwiftUI

/// Drags library videos out of the app as plain file URLs (accepted by Finder, the Desktop, chat apps),
/// offering only "copy" so a drop can never move the original out of the library.
@MainActor
public final class FileDragSource: NSObject, NSDraggingSource {
    public static let shared = FileDragSource()

    /// The drag in progress. AppKit keeps a session alive only while it runs, so this clears itself
    /// even if a session ends without calling back.
    private weak var session: NSDraggingSession?

    /// True while a drag session is running.
    public var isDragging: Bool { session != nil }

    /// Copy when dropped outside the app; nothing inside the app accepts these drops.
    public static func operationMask(for context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.operationMask(for: context)
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                operation: NSDragOperation) {
        self.session = nil
    }

    /// Starts a drag of `urls` from the current mouse event (call from a drag gesture).
    public func begin(_ urls: [URL]) {
        guard !isDragging, !urls.isEmpty,
              let event = NSApp.currentEvent,
              event.type == .leftMouseDragged, // a real drag, never a plain click
              let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let session = view.beginDraggingSession(with: fileDragItems(for: urls, at: point), event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        self.session = session
    }
}

/// One dragging item per file, centred on `point`, showing the file's Finder icon.
@MainActor
public func fileDragItems(for urls: [URL], at point: NSPoint) -> [NSDraggingItem] {
    let size = NSSize(width: 64, height: 64)
    return urls.enumerated().map { index, url in
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let offset = CGFloat(index) * 8
        let frame = NSRect(x: point.x - size.width / 2 + offset, y: point.y - size.height / 2 - offset,
                           width: size.width, height: size.height)
        item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
        return item
    }
}

extension View {
    /// Lets the user drag this view out of the app as a copy of the file at `url`.
    /// Uses a simultaneous gesture so clicks, double-clicks and right-clicks still work.
    public func fileDraggable(_ url: URL) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { _ in FileDragSource.shared.begin([url]) }
        )
    }
}
