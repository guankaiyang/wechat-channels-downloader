import DownloaderCore
import SwiftUI

/// A 3:4 thumbnail tile with the video's length in the corner.
/// The tile's shape is fixed first; the picture fills it and is clipped to it, so
/// landscape or tall videos never spill over neighbouring cards.
public struct ThumbnailFrame: View {
    let image: CGImage?
    let duration: Double?

    public init(image: CGImage?, duration: Double?) {
        self.image = image
        self.duration = duration
    }

    public var body: some View {
        Theme.surfaceRaised.color
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film").font(.title).foregroundStyle(Theme.textSecondary.color)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration {
                    Text(formatDuration(duration))
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.onAccent.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.accent.color, in: Capsule())
                        .padding(6)
                }
            }
            .clipped()
    }
}
