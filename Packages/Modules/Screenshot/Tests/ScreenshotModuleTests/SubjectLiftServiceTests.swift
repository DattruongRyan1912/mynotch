import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct SubjectLiftServiceTests {
    @Test func subjectLiftMessageProperties() {
        #expect(SubjectLiftMessage.lifting.isProcessing == true)
        #expect(SubjectLiftMessage.lifting.text == "Đang tách chủ thể…")
        #expect(SubjectLiftMessage.noSubject.isProcessing == false)
        #expect(SubjectLiftMessage.noSubject.text == "Không tìm thấy chủ thể")
        #expect(SubjectLiftMessage.lifted.isProcessing == false)
        #expect(SubjectLiftMessage.lifted.text == "Đã tách & chép chủ thể")
        #expect(SubjectLiftMessage.failed.isProcessing == false)
        #expect(SubjectLiftMessage.failed.text == "Không tách được chủ thể")
    }

    @Test func cropToNonTransparentBoundsCropsTightBox() {
        let size = CGSize(width: 100, height: 100)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }

        // Fill background with transparent
        context.clear(CGRect(origin: .zero, size: size))

        // Draw opaque red rectangle in the center (x: 40, y: 30, w: 25, h: 45)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 30, width: 25, height: 45))

        guard let testImage = context.makeImage() else {
            Issue.record("Failed to make testImage")
            return
        }

        let cropped = SubjectLiftService.cropToNonTransparentBounds(testImage)
        #expect(cropped != nil)
        #expect(cropped?.width == 25)
        #expect(cropped?.height == 45)
    }

    @Test func cropToNonTransparentBoundsReturnsNilForFullyTransparentImage() {
        let size = CGSize(width: 60, height: 60)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }

        context.clear(CGRect(origin: .zero, size: size))
        guard let blankImage = context.makeImage() else {
            Issue.record("Failed to make blankImage")
            return
        }

        let cropped = SubjectLiftService.cropToNonTransparentBounds(blankImage)
        #expect(cropped == nil)
    }

    @Test func applyAlphaMaskCropsToSubjectBounds() {
        let size = CGSize(width: 80, height: 80)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let sourceContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let maskContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create contexts")
            return
        }

        sourceContext.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        sourceContext.fill(CGRect(origin: .zero, size: size))
        guard let source = sourceContext.makeImage() else { return }

        maskContext.clear(CGRect(origin: .zero, size: size))
        maskContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        maskContext.fill(CGRect(x: 20, y: 25, width: 30, height: 35))
        guard let mask = maskContext.makeImage() else { return }

        let result = SubjectLiftService.applyAlphaMask(mask, to: source, cropToBounds: true)
        #expect(result != nil)
        #expect(result?.width == 30)
        #expect(result?.height == 35)
    }
}
