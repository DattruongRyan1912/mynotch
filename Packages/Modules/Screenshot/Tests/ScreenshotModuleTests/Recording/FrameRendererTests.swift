import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import ScreenshotModule

/// BGRA pixel buffers made and read in memory.
enum PixelBuffers {
    typealias Pixel = (b: UInt8, g: UInt8, r: UInt8)

    static func make(width: Int, height: Int, pixel: (Int, Int) -> Pixel) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let offset = y * rowBytes + x * 4
                base[offset] = value.b
                base[offset + 1] = value.g
                base[offset + 2] = value.r
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }

    static func solid(width: Int, height: Int, grey: UInt8) -> CVPixelBuffer {
        make(width: width, height: height) { _, _ in (grey, grey, grey) }
    }

    static func read(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Pixel {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return (base[offset], base[offset + 1], base[offset + 2])
    }

    static func bytes(_ buffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var result: [UInt8] = []
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            result += UnsafeBufferPointer(start: base + y * rowBytes, count: CVPixelBufferGetWidth(buffer) * 4)
        }
        return result
    }
}

@Suite struct FrameRendererTests {
    let renderer = FrameRenderer()

    /// Blue grows to the right and green grows downwards: every pixel says where it is, and a flipped or mirrored result shows.
    func ramp(width: Int = 80, height: Int = 60) -> CVPixelBuffer {
        PixelBuffers.make(width: width, height: height) { x, y in (UInt8(x * 3), UInt8(y * 4), 0) }
    }

    func destination(_ width: Int, _ height: Int) -> CVPixelBuffer { PixelBuffers.solid(width: width, height: height, grey: 0) }

    func near(_ pixel: PixelBuffers.Pixel, blue: Double, green: Double, within tolerance: Double = 4) -> Bool {
        abs(Double(pixel.b) - blue) <= tolerance && abs(Double(pixel.g) - green) <= tolerance
    }

    @Test func aFrameThatIsNeitherCroppedNorScaledLeavesExactlyAsItCame() {
        let source = ramp()
        let output = destination(80, 60)

        renderer.render(source: source, crop: CGRect(x: 0, y: 0, width: 80, height: 60), rings: [], into: output)

        #expect(PixelBuffers.bytes(output) == PixelBuffers.bytes(source))
    }

    @Test func aCropIsScaledToFillTheOutputAndTheRightWayUp() {
        let output = destination(80, 60)

        // The middle part, 40×30 from (20, 10), shown at twice the size. Pixel centres are half a pixel in: the top-left
        // output pixel looks at x = 20.25 and y = 10.25.
        renderer.render(source: ramp(), crop: CGRect(x: 20, y: 10, width: 40, height: 30), rings: [], into: output)

        #expect(near(PixelBuffers.read(output, x: 0, y: 0), blue: 3 * 19.75, green: 4 * 9.75))
        #expect(near(PixelBuffers.read(output, x: 79, y: 0), blue: 3 * 59.75, green: 4 * 9.75))
        #expect(near(PixelBuffers.read(output, x: 0, y: 59), blue: 3 * 19.75, green: 4 * 39.75))
        #expect(near(PixelBuffers.read(output, x: 79, y: 59), blue: 3 * 59.75, green: 4 * 39.75))
    }

    @Test func aCropAtAnAsymmetricPlaceShowsThatPlaceNotItsMirrorImage() {
        let output = destination(40, 30)

        // A quarter of the width in and a fifth of the height down, a quarter of the picture in size.
        renderer.render(source: ramp(), crop: CGRect(x: 20, y: 12, width: 20, height: 15), rings: [], into: output)

        let top = PixelBuffers.read(output, x: 20, y: 0)
        let bottom = PixelBuffers.read(output, x: 20, y: 29)
        #expect(near(top, blue: 3 * 29.75, green: 4 * 12.25, within: 6))
        #expect(near(bottom, blue: 3 * 29.75, green: 4 * 26.75, within: 6))
        #expect(top.g < bottom.g)
    }

    @Test func aSmallerOutputShowsTheWholePictureScaledDown() {
        let output = destination(40, 30)

        renderer.render(source: ramp(), crop: CGRect(x: 0, y: 0, width: 80, height: 60), rings: [], into: output)

        // A pixel of the output is the mean of two, one more than the left one's centre.
        #expect(near(PixelBuffers.read(output, x: 0, y: 0), blue: 3 * 1, green: 4 * 1, within: 5))
        #expect(near(PixelBuffers.read(output, x: 39, y: 29), blue: 3 * 79, green: 4 * 59, within: 5))
    }

    @Test func aCropThatMovesByAFractionOfAPixelMovesTheImageByAFraction() {
        let a = destination(80, 60), b = destination(80, 60)

        renderer.render(source: ramp(), crop: CGRect(x: 10, y: 10, width: 40, height: 30), rings: [], into: a)
        renderer.render(source: ramp(), crop: CGRect(x: 10.5, y: 10, width: 40, height: 30), rings: [], into: b)

        // 0.5 source pixel is 1 output pixel at this scale, and a blue ramp of 3 per source pixel: 3 more in b.
        let shift = Double(PixelBuffers.read(b, x: 30, y: 20).b) - Double(PixelBuffers.read(a, x: 30, y: 20).b)
        #expect(abs(shift - 1.5) < 2)
    }

    @Test func aSourceThatIsMissingLeavesBlack() {
        let output = PixelBuffers.solid(width: 20, height: 10, grey: 200)

        renderer.render(source: nil, crop: CGRect(x: 0, y: 0, width: 20, height: 10), rings: [], into: output)

        #expect(PixelBuffers.read(output, x: 5, y: 5) == (0, 0, 0))
    }

    // MARK: Rings

    func ring(x: Double, y: Double, radius: Double, opacity: Double = 1) -> ClickEffect.Ring {
        .init(x: x, y: y, radius: radius, opacity: opacity)
    }

    @Test func aRingIsDrawnAtTheClickThatIsNearTheTopLeftAndNotAtItsMirrorImage() {
        let source = PixelBuffers.solid(width: 200, height: 120, grey: 60)
        let output = destination(200, 120)

        // A click at a quarter of the width and a fifth of the height.
        renderer.render(
            source: source, crop: CGRect(x: 0, y: 0, width: 200, height: 120), rings: [ring(x: 50, y: 24, radius: 12)], into: output
        )

        let onRing = PixelBuffers.read(output, x: 62, y: 24)
        let inside = PixelBuffers.read(output, x: 50, y: 24)
        #expect(onRing.r > 200 && onRing.g > 200 && onRing.b > 200)
        #expect(inside.b > inside.r + 20, "the inside of the ring is tinted blue")
        for mirrored in [(150, 24), (50, 96), (150, 96), (24, 50)] {
            #expect(PixelBuffers.read(output, x: mirrored.0, y: mirrored.1) == (60, 60, 60), "at \(mirrored)")
        }
        #expect(PixelBuffers.read(output, x: 100, y: 60) == (60, 60, 60))
    }

    @Test func aRingMovesAndGrowsWithTheCameraThatZoomsOnIt() {
        let source = PixelBuffers.solid(width: 200, height: 120, grey: 60)
        let output = destination(200, 120)

        // The camera looks at the right half of the top half, twice as close: the click at (125, 30) is at (50, 60) there, and
        // a ring of radius 10 is 20 wide.
        renderer.render(
            source: source, crop: CGRect(x: 100, y: 0, width: 100, height: 60), rings: [ring(x: 125, y: 30, radius: 10)], into: output
        )

        let onRing = PixelBuffers.read(output, x: 70, y: 60)
        #expect(onRing.r > 200 && onRing.g > 200 && onRing.b > 200)
        #expect(PixelBuffers.read(output, x: 62, y: 60).r < 200, "a ring of the original size would not reach here, one scaled up does")
        #expect(PixelBuffers.read(output, x: 125, y: 30) == (60, 60, 60))
    }

    @Test func aRingFadesWithItsOpacityAndIsGoneAtZero() {
        let source = PixelBuffers.solid(width: 200, height: 120, grey: 60)
        let faint = destination(200, 120), gone = destination(200, 120)

        renderer.render(source: source, crop: CGRect(x: 0, y: 0, width: 200, height: 120), rings: [ring(x: 100, y: 60, radius: 20, opacity: 0.3)], into: faint)
        renderer.render(source: source, crop: CGRect(x: 0, y: 0, width: 200, height: 120), rings: [ring(x: 100, y: 60, radius: 20, opacity: 0)], into: gone)

        let faintPixel = PixelBuffers.read(faint, x: 120, y: 60)
        #expect(faintPixel.r > 70 && faintPixel.r < 200)
        #expect(PixelBuffers.read(gone, x: 120, y: 60) == (60, 60, 60))
    }

    @Test func aRingOutsideTheCameraOrBeyondTheEdgeIsHarmless() {
        let source = PixelBuffers.solid(width: 200, height: 120, grey: 60)
        let output = destination(200, 120)

        renderer.render(
            source: source, crop: CGRect(x: 0, y: 0, width: 200, height: 120),
            rings: [ring(x: -300, y: 50, radius: 20), ring(x: 9_000, y: 9_000, radius: 20), ring(x: 0, y: 0, radius: 15)], into: output
        )

        #expect(PixelBuffers.read(output, x: 100, y: 60) == (60, 60, 60))
        // The one on the corner is cut by the edge but its part that is inside is drawn.
        #expect(PixelBuffers.read(output, x: 15, y: 0).r > 150)
    }
}
