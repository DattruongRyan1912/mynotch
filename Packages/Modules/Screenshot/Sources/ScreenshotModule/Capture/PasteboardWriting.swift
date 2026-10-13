import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Puts captures and recognised text on a pasteboard. A protocol so tests never write to the real one.
protocol PasteboardWriting: AnyObject {
    /// Replaces the pasteboard's contents with `image` as PNG and TIFF; `scale` (pixels per point) sets their DPI.
    /// False when the pasteboard refused the data.
    func write(_ image: CGImage, scale: CGFloat) async -> Bool

    /// Replaces the pasteboard's contents with `text`.
    func write(_ text: String) -> Bool
}

/// Writes to a real pasteboard, the general one by default. It adds no marker type: the Clipboard module records
/// screenshots like any other image.
final class SystemPasteboard: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ image: CGImage, scale: CGFloat) async -> Bool {
        // Encoding a large capture twice takes a while, hence off the main actor.
        guard let png = try? await CaptureStore.pngData(image, scale: scale),
              let tiff = await Self.tiffData(image, scale: scale) else { return false }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    func write(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// LZW-compressed: an uncompressed TIFF of a 6K screen would be some 80 MB.
    @concurrent
    private nonisolated static func tiffData(_ image: CGImage, scale: CGFloat) async -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else { return nil }
        let properties = [
            kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
