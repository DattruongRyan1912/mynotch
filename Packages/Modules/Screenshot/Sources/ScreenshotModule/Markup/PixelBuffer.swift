import CoreGraphics
import Foundation

/// A rectangle of whole pixels: `columns` left to right and `rows` top to bottom, like the bytes of a bitmap.
nonisolated struct PixelRegion: Equatable, Sendable {
    var columns: Range<Int>
    var rows: Range<Int>

    init(columns: Range<Int>, rows: Range<Int>) {
        self.columns = columns
        self.rows = rows
    }

    /// `rect` rounded outward to whole pixels, then cut to a `width` × `height` bitmap, so a rectangle that was only
    /// partly selected still covers every pixel it touched and one that left the picture stays inside it.
    init(rect: CGRect, within width: Int, _ height: Int) {
        let rounded = rect.standardized.integral
        let clipped = rounded.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        if clipped.isNull || clipped.isEmpty {
            self.init(columns: 0..<0, rows: 0..<0)
        } else {
            self.init(columns: Int(clipped.minX)..<Int(clipped.maxX), rows: Int(clipped.minY)..<Int(clipped.maxY))
        }
    }

    var isEmpty: Bool { columns.isEmpty || rows.isEmpty }

    /// Grown by `amount` pixels on every side; not clipped, so clip it against the bitmap before reading.
    func outset(by amount: Int) -> PixelRegion {
        PixelRegion(columns: (columns.lowerBound - amount)..<(columns.upperBound + amount), rows: (rows.lowerBound - amount)..<(rows.upperBound + amount))
    }

    /// Shrunk by `amount` pixels on every side, down to nothing.
    func inset(by amount: Int) -> PixelRegion {
        func shrink(_ range: Range<Int>) -> Range<Int> {
            let lower = range.lowerBound + amount, upper = range.upperBound - amount
            return lower < upper ? lower..<upper : range.lowerBound..<range.lowerBound
        }
        return PixelRegion(columns: shrink(columns), rows: shrink(rows))
    }

    /// The part inside `other`; empty when they do not meet.
    func clipped(to other: PixelRegion) -> PixelRegion {
        PixelRegion(columns: Self.overlap(columns, other.columns), rows: Self.overlap(rows, other.rows))
    }

    private static func overlap(_ a: Range<Int>, _ b: Range<Int>) -> Range<Int> {
        let lower = max(a.lowerBound, b.lowerBound)
        return lower..<max(lower, min(a.upperBound, b.upperBound))
    }
}

/// One RGBA8 pixel exactly as a premultiplied bitmap stores it.
nonisolated struct RawPixel: Equatable, Sendable {
    var red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8

    static let white = RawPixel(red: 255, green: 255, blue: 255, alpha: 255)
    static let black = RawPixel(red: 0, green: 0, blue: 0, alpha: 255)
}

/// The bytes of a premultiplied RGBA8 bitmap context, top row first, for the effects that work on pixels.
nonisolated struct PixelBuffer {
    let data: UnsafeMutableRawPointer
    let width: Int
    let height: Int
    let bytesPerRow: Int

    /// nil when the context keeps no bitmap of its own.
    init?(_ context: CGContext) {
        context.flush()
        guard let data = context.data else { return nil }
        self.data = data
        width = context.width
        height = context.height
        bytesPerRow = context.bytesPerRow
    }

    var region: PixelRegion { PixelRegion(columns: 0..<width, rows: 0..<height) }

    func pixel(_ x: Int, _ y: Int) -> RawPixel {
        let bytes = (data + y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
        return RawPixel(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes[3])
    }

    /// Overwrites `region` (inside the bitmap) with `pixel`.
    func fill(_ region: PixelRegion, with pixel: RawPixel) {
        guard !region.isEmpty else { return }
        var pattern = [pixel.red, pixel.green, pixel.blue, pixel.alpha]
        for y in region.rows {
            memset_pattern4(data + y * bytesPerRow + region.columns.lowerBound * 4, &pattern, region.columns.count * 4)
        }
    }
}
