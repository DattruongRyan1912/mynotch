import CoreGraphics
import Foundation
import Testing

/// An sRGB RGBA8 pixel grid addressed like the markup model: origin at the top-left, y down.
struct Bitmap {
    struct Pixel: Equatable, CustomStringConvertible {
        var r, g, b, a: UInt8
        static let white = Pixel(r: 255, g: 255, b: 255, a: 255)
        static let black = Pixel(r: 0, g: 0, b: 0, a: 255)
        var description: String { "(\(r), \(g), \(b), \(a))" }
    }

    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int, pixel: (_ x: Int, _ y: Int) -> Pixel) {
        self.width = width
        self.height = height
        bytes = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                bytes += [value.r, value.g, value.b, value.a]
            }
        }
    }

    /// Reads `image` back by drawing it into an sRGB bitmap; bitmap memory starts at the top row.
    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: Self.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try #require(context.data)
        bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func checkerboard(width: Int, height: Int) -> Bitmap {
        Bitmap(width: width, height: height) { x, y in (x + y).isMultiple(of: 2) ? .black : .white }
    }

    static func filled(width: Int, height: Int, with pixel: Pixel = .white) -> Bitmap {
        Bitmap(width: width, height: height) { _, _ in pixel }
    }

    func pixel(_ x: Int, _ y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        return Pixel(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
    }

    func image() throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: Self.space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
