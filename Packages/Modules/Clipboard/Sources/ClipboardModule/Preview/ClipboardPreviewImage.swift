import CoreGraphics
import Foundation

/// Where the preview reads a picture from. Never a copy on disk: a picture of an open locked board is bytes in memory, any other
/// is its stored file, read.
enum ClipboardPreviewImageSource: Equatable, Sendable {
    case file(URL)
    case memory(Data)
}

/// The picture of a preview, decoded by ImageIO at the size it is drawn at, so a 12-megapixel screenshot is never held at full size.
enum ClipboardPreviewImage {
    typealias Source = ClipboardPreviewImageSource

    /// The most pixels on a side. A picture twice as wide as a 5K display gains nothing from more, and each pixel costs four bytes.
    nonisolated static let pixelCap = 5120

    /// The longest side, in pixels, to decode a picture of `pixelWidth` x `pixelHeight` for a view of `display` points on a screen
    /// of `scale` pixels per point: what it takes to draw the picture fitted into the view, never more than the picture has and never
    /// more than `pixelCap`. A picture whose size is not known gets what the view could show of anything.
    nonisolated static func maxPixelSize(display: CGSize, scale: CGFloat, pixelWidth: Int, pixelHeight: Int) -> Int {
        let viewWidth = max(display.width * scale, 1), viewHeight = max(display.height * scale, 1)
        guard pixelWidth > 0, pixelHeight > 0 else { return min(Int(ceil(max(viewWidth, viewHeight))), pixelCap) }
        let fit = min(1, min(viewWidth / Double(pixelWidth), viewHeight / Double(pixelHeight)))
        let longest = Double(max(pixelWidth, pixelHeight)) * fit
        return max(1, min(Int(ceil(longest)), pixelCap))
    }

    /// nil when the bytes are not a picture or the file is not there. Off the main actor; only reads.
    @concurrent static func load(_ source: Source, maxPixelSize: Int) async -> CGImage? {
        switch source {
        case .file(let url): await ClipboardThumbnailCache.decode(url, maxPixelSize: maxPixelSize)
        case .memory(let data): await ClipboardThumbnailCache.decode(data, maxPixelSize: maxPixelSize)
        }
    }
}
