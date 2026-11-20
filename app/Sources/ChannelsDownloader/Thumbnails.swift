import AVFoundation
import AppViews
import DownloaderCore
import QuickLookThumbnailing
import SwiftUI

/// Thumbnails and lengths, cached per file version so rewritten downloads refresh.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [ThumbnailKey: CGImage] = [:]
    private var durations: [ThumbnailKey: Double] = [:]

    func thumbnail(for key: ThumbnailKey) async -> CGImage? {
        if let cached = images[key] { return cached }
        guard let image = await makeThumbnail(url: key.url) else { return nil }
        images[key] = image
        return image
    }

    func duration(for key: ThumbnailKey) async -> Double? {
        if let cached = durations[key] { return cached }
        guard let seconds = await loadDuration(url: key.url) else { return nil }
        durations[key] = seconds
        return seconds
    }
}

private func makeThumbnail(url: URL) async -> CGImage? {
    let request = QLThumbnailGenerator.Request(
        fileAt: url, size: CGSize(width: 360, height: 480), scale: 2, representationTypes: .thumbnail)
    return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
}

private func loadDuration(url: URL) async -> Double? {
    guard let time = try? await AVURLAsset(url: url).load(.duration) else { return nil }
    let seconds = time.seconds
    return seconds.isFinite && seconds > 0 ? seconds : nil
}

/// A video's thumbnail with its length in the corner, loaded in the background.
struct ThumbnailView: View {
    let item: VideoItem
    var showsDuration = true
    @ViewState private var image: CGImage?
    @ViewState private var duration: Double?

    var body: some View {
        ThumbnailFrame(image: image, duration: showsDuration ? duration : nil)
            .task(id: ThumbnailKey(item)) {
                let key = ThumbnailKey(item)
                image = await ThumbnailCache.shared.thumbnail(for: key)
                duration = await ThumbnailCache.shared.duration(for: key)
            }
    }
}

/// Just the length, for the list view.
struct DurationText: View {
    let item: VideoItem
    @ViewState private var duration: Double?

    var body: some View {
        Text(duration.map(formatDuration) ?? "–")
            .monospacedDigit()
            .task(id: ThumbnailKey(item)) {
                duration = await ThumbnailCache.shared.duration(for: ThumbnailKey(item))
            }
    }
}
