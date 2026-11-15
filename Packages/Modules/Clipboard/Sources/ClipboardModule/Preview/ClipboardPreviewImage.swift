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

    /// How long a picture waits, once it is selected, before it is decoded. Holding ↓ over big pictures selects each for a moment and
    /// replaces it; with the wait, the views that go cancel their tasks before any decode is started.
    nonisolated static let pause: Duration = .milliseconds(80)

    /// nil when the bytes are not a picture or the file is not there, or when the task was cancelled before the decode began (a
    /// decode that has begun runs to its end, so it is the start that is guarded). Off the main actor; only reads.
    @concurrent static func load(_ source: Source, maxPixelSize: Int, decoder: ClipboardPreviewImageDecoder = .system) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        switch source {
        case .file(let url): return await decoder.file(url, maxPixelSize)
        case .memory(let data): return await decoder.memory(data, maxPixelSize)
        }
    }

    /// `load` after `pause`, which a cancellation cuts short: what the preview's pane asks for. `sleep` is how the pause is waited
    /// out, a parameter so a test can hold the tasks in it without a clock.
    @concurrent static func loadAfterPause(
        _ source: Source, maxPixelSize: Int, pause: Duration = ClipboardPreviewImage.pause,
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        decoder: ClipboardPreviewImageDecoder = .system
    ) async -> CGImage? {
        await sleep(pause)
        return await load(source, maxPixelSize: maxPixelSize, decoder: decoder)
    }
}

/// The two ways a picture is decoded, as a value so a test counts the decodes instead of making them.
nonisolated struct ClipboardPreviewImageDecoder: Sendable {
    var file: @Sendable (URL, Int) async -> CGImage?
    var memory: @Sendable (Data, Int) async -> CGImage?

    /// ImageIO at the size asked for, the call the thumbnails use.
    static let system = ClipboardPreviewImageDecoder(
        file: { await ClipboardThumbnailCache.decode($0, maxPixelSize: $1) },
        memory: { await ClipboardThumbnailCache.decode($0, maxPixelSize: $1) }
    )
}
