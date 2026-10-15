import CoreGraphics
import Foundation
import ImageIO

/// Finds the colours an album cover is mostly made of: the cover is shrunk to at most 64 by 64, its pixels are grouped by
/// k-means, and the groups that cover the most of it, favouring vivid ones over greys, are the tint. Pure, deterministic and
/// free of the main actor, so it runs on a background task.
nonisolated enum ArtworkColorExtractor {
    /// The longest side of what is looked at: the colours of a cover do not need more, and the work stays tiny.
    static let maxDimension: CGFloat = 64
    /// Groups of pixels the k-means makes; the one or two best become the tint.
    static let groupCount = 4
    static let maxIterations = 12
    /// The second colour has to differ from the first by at least this much, 0...√3 across the channels.
    static let minimumSeparation = 0.25
    /// And has to be at least this part of the cover, so a speck does not become the second tint.
    static let minimumShare = 0.06
    /// Pixels that are less opaque than this say nothing about the cover.
    static let minimumAlpha = 0.5
    /// A group of this part of the picture counts for less when it is grey: its weight is share × (this + saturation).
    static let saturationBias = 0.3

    private struct Group {
        var color: SRGBColor
        var share: Double
        var weight: Double { share * (saturationBias + color.saturation) }
    }

    /// What `size` shrinks to so that its longer side is `maxDimension`; never larger than it is, never under a pixel. nil for an
    /// image with no area.
    static func sampleSize(for size: CGSize) -> CGSize? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// The tint of encoded image data (PNG, JPEG, ...), read as a thumbnail so a big cover is never decoded in full. nil for
    /// data that is no image, or an image with no opaque pixel.
    static func palette(imageData: Data) -> ArtworkPalette? {
        guard !imageData.isEmpty, let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return palette(of: thumbnail)
    }

    /// The tint of `image`, drawn at `sampleSize` in sRGB first.
    static func palette(of image: CGImage) -> ArtworkPalette? {
        guard let size = sampleSize(for: CGSize(width: image.width, height: image.height)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (Int(size.width), Int(size.height))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return palette(premultipliedRGBA: bytes)
    }

    /// The tint of the pixels in `bytes`, four per pixel, red, green, blue and alpha, premultiplied.
    static func palette(premultipliedRGBA bytes: [UInt8]) -> ArtworkPalette? {
        var pixels: [SRGBColor] = []
        pixels.reserveCapacity(bytes.count / 4)
        for offset in stride(from: 0, to: bytes.count - 3, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha >= minimumAlpha else { continue }
            pixels.append(SRGBColor(
                red: Double(bytes[offset]) / 255 / alpha, green: Double(bytes[offset + 1]) / 255 / alpha,
                blue: Double(bytes[offset + 2]) / 255 / alpha
            ))
        }
        return palette(pixels: pixels)
    }

    static func palette(pixels: [SRGBColor]) -> ArtworkPalette? {
        let groups = groups(of: pixels)
        guard let primary = best(of: groups) else { return nil }
        let separate = groups.filter { $0.share >= minimumShare && $0.color.distance(to: primary.color) >= minimumSeparation }
        let first = primary.color.lifted(toLuminance: SRGBColor.minimumLuminance)
        var second = best(of: separate)?.color.lifted(toLuminance: SRGBColor.minimumLuminance)
        // Two dark colours can end up as the same grey once they are lifted.
        if let lifted = second, lifted.distance(to: first) < minimumSeparation / 2 { second = nil }
        return ArtworkPalette(primary: first, secondary: second)
    }

    /// The group that weighs most; of equal weights the brighter, which shows better on black.
    private static func best(of groups: [Group]) -> Group? {
        groups.max { a, b in
            a.weight != b.weight ? a.weight < b.weight : a.color.luminance < b.color.luminance
        }
    }

    /// k-means on the pixels' channels. The seeds are pixels at evenly spaced ranks of the pixels sorted by luminance, so the
    /// same picture always gives the same groups and a few stray pixels cannot take a seed of their own. Seeds that coincide
    /// leave a group empty; empty groups are dropped.
    private static func groups(of pixels: [SRGBColor]) -> [Group] {
        guard !pixels.isEmpty else { return [] }
        let count = min(groupCount, pixels.count)
        let sorted = pixels.map { (luminance: $0.luminance, color: $0) }.sorted { $0.luminance < $1.luminance }
        var centres = (0..<count).map { sorted[(2 * $0 + 1) * sorted.count / (2 * count)].color }
        var assignment = [Int](repeating: -1, count: pixels.count)
        var members = [Int](repeating: 0, count: count)
        for _ in 0..<maxIterations {
            var sums = [(red: Double, green: Double, blue: Double)](repeating: (0, 0, 0), count: count)
            members = [Int](repeating: 0, count: count)
            var changed = false
            for (index, pixel) in pixels.enumerated() {
                var nearest = 0
                var nearestDistance = Double.infinity
                for (group, centre) in centres.enumerated() {
                    let distance = pixel.squaredDistance(to: centre)
                    if distance < nearestDistance { (nearest, nearestDistance) = (group, distance) }
                }
                if assignment[index] != nearest {
                    assignment[index] = nearest
                    changed = true
                }
                members[nearest] += 1
                sums[nearest].red += pixel.red
                sums[nearest].green += pixel.green
                sums[nearest].blue += pixel.blue
            }
            for group in 0..<count where members[group] > 0 {
                let size = Double(members[group])
                centres[group] = SRGBColor(red: sums[group].red / size, green: sums[group].green / size, blue: sums[group].blue / size)
            }
            if !changed { break }
        }
        let total = Double(pixels.count)
        return (0..<count).filter { members[$0] > 0 }.map { Group(color: centres[$0], share: Double(members[$0]) / total) }
    }
}
