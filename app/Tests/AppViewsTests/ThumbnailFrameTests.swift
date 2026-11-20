import AppKit
import AppViews
import SwiftUI
import Testing

private func solidImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

/// Renders a blue 60-pt strip with a 170-pt-wide card to its right (as in the grid),
/// so any thumbnail spilling out of its card paints over the strip.
@MainActor
private func renderCardBesideStrip(_ image: CGImage?) throws -> NSBitmapImageRep {
    let content = HStack(alignment: .top, spacing: 0) {
        Color.blue.frame(width: 60, height: 300)
        ThumbnailFrame(image: image, duration: 92).frame(width: 170)
    }
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
}

private func isBlue(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
    return c.blueComponent > 0.8 && c.redComponent < 0.2
}

@MainActor
@Suite struct ThumbnailFrameTests {
    @Test func landscapeVideoStaysInsideItsCard() throws {
        let rep = try renderCardBesideStrip(try solidImage(width: 1920, height: 1080))
        #expect(isBlue(rep, x: 30, y: 100))
    }

    @Test func portraitVideoKeepsCardShape() throws {
        let renderer = ImageRenderer(content: ThumbnailFrame(image: try solidImage(width: 1080, height: 1920), duration: 92)
            .frame(width: 170))
        let size = try #require(renderer.nsImage).size
        #expect(abs(size.height - 170 * 4 / 3) < 1)
    }

    @Test func placeholderKeepsCardShape() throws {
        let renderer = ImageRenderer(content: ThumbnailFrame(image: nil, duration: nil).frame(width: 170))
        let size = try #require(renderer.nsImage).size
        #expect(abs(size.height - 170 * 4 / 3) < 1)
    }
}

@MainActor
@Suite struct DurationChipTests {
    @Test func durationChipIsAccentGreen() throws {
        let renderer = ImageRenderer(content: ThumbnailFrame(image: nil, duration: 92).frame(width: 170))
        renderer.scale = 1
        let rep = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        // Inside the chip's right padding, vertically centred (chip sits 6 pt from the corner).
        let color = try #require(rep.colorAt(x: rep.pixelsWide - 6 - 3, y: rep.pixelsHigh - 6 - 9)?.usingColorSpace(.deviceRGB))
        #expect(color.greenComponent > 0.6 && color.redComponent < 0.2, "chip pixel \(color)")
    }
}
