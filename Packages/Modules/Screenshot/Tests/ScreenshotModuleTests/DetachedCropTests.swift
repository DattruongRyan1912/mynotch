import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct DetachedCropTests {
    @Test func cropHasTheRegionsPixelsAndSize() throws {
        let source = try Bitmap(width: 200, height: 160) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 7, a: 255) }.image()

        let crop = try #require(source.detachedCrop(to: CGRect(x: 20, y: 30, width: 40, height: 50)))

        #expect((crop.width, crop.height) == (40, 50))
        let bitmap = try Bitmap(crop)
        #expect(bitmap.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 7, a: 255))
        #expect(bitmap.pixel(39, 49) == Bitmap.Pixel(r: 59, g: 79, b: 7, a: 255))
    }

    @Test func cropDoesNotKeepTheParentAlive() throws {
        weak var parent: CGImage?
        var plain: CGImage?
        var detached: CGImage?
        do {
            let source = try Bitmap.checkerboard(width: 100, height: 100).image()
            parent = source
            plain = source.cropping(to: CGRect(x: 10, y: 10, width: 20, height: 20))
            detached = source.detachedCrop(to: CGRect(x: 10, y: 10, width: 20, height: 20))
        }
        // `cropping(to:)` holds on to the whole parent, which is what a detached copy exists to avoid.
        #expect(plain?.width == 20)
        #expect(parent != nil)
        plain = nil
        #expect(parent == nil)
        #expect(detached?.width == 20)
        #expect(detached?.colorSpace?.name == Bitmap.space.name)
    }

    @Test func aRegionOutsideTheImageIsNil() throws {
        let source = try Bitmap.filled(width: 10, height: 10).image()
        #expect(source.detachedCrop(to: CGRect(x: 50, y: 50, width: 5, height: 5)) == nil)
    }

    @Test func theWholeImageIsReturnedAsItIs() throws {
        let source = try Bitmap.filled(width: 10, height: 10).image()
        let crop = try #require(source.detachedCrop(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect((crop.width, crop.height) == (10, 10))
    }
}
