import CoreGraphics
import Foundation
@testable import ScreenshotModule
import Testing

@Suite("LongCaptureStitcher Tests")
struct LongCaptureStitcherTests {
    private func makePatternFrame(width: Int = 120, startY: Int, windowHeight: Int = 100) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixelData = [UInt8](repeating: 0, count: width * windowHeight * 4)

        for y in 0..<windowHeight {
            let docY = startY + y
            let r = UInt8((docY * 17 + 23) % 256)
            let g = UInt8((docY * 31 + 47) % 256)
            let b = UInt8((docY * 53 + 89) % 256)
            let a: UInt8 = 255
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let xMod = UInt8((x * 7) % 30)
                pixelData[offset] = r ^ xMod
                pixelData[offset + 1] = g ^ xMod
                pixelData[offset + 2] = b ^ xMod
                pixelData[offset + 3] = a
            }
        }

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: windowHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        return context.makeImage()!
    }

    @Test func stitchesConsecutiveScrollingFramesSeamlessly() {
        let frame1 = makePatternFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)
        #expect(stitcher.canvas.height == 100)

        // Frame 2 is scrolled down by 30px
        let frame2 = makePatternFrame(startY: 30)
        let outcome2 = stitcher.append(frame2)
        #expect(outcome2 == .appended(shift: 30, newTotalHeight: 130))
        #expect(stitcher.canvas.height == 130)

        // Frame 3 is scrolled down by 25px further (startY: 55)
        let frame3 = makePatternFrame(startY: 55)
        let outcome3 = stitcher.append(frame3)
        #expect(outcome3 == .appended(shift: 25, newTotalHeight: 155))
        #expect(stitcher.canvas.height == 155)
    }

    @Test func duplicateFrameReportsUnchanged() {
        let frame1 = makePatternFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)

        let duplicate = makePatternFrame(startY: 0)
        let outcome = stitcher.append(duplicate)
        #expect(outcome == .unchanged)
        #expect(stitcher.canvas.height == 100)
    }

    @Test func mismatchedWidthOrNoOverlapReportsNoOverlap() {
        let frame1 = makePatternFrame(width: 120, startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)

        // Different width
        let differentWidth = makePatternFrame(width: 140, startY: 20)
        let outcome1 = stitcher.append(differentWidth)
        #expect(outcome1 == .noOverlap)

        // Huge jump with zero overlap (jump from 0 to 500)
        let disjoint = makePatternFrame(width: 120, startY: 500)
        let outcome2 = stitcher.append(disjoint)
        #expect(outcome2 == .noOverlap)
    }

    @Test func stopsAtMaxCanvasHeight() {
        let frame1 = makePatternFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1, maxCanvasHeight: 125)

        // Scroll by 30px -> would be 130px > 125px
        let frame2 = makePatternFrame(startY: 30)
        let outcome = stitcher.append(frame2)
        #expect(outcome == .reachedMaxHeight)
        #expect(stitcher.canvas.height == 100)
    }

    private func makeWhitespaceBottomFrame(width: Int = 120, startY: Int, windowHeight: Int = 100, blankHeight: Int = 30) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixelData = [UInt8](repeating: 255, count: width * windowHeight * 4)

        let contentHeight = windowHeight - blankHeight
        for y in 0..<contentHeight {
            let docY = startY + y
            let r = UInt8((docY * 17 + 23) % 256)
            let g = UInt8((docY * 31 + 47) % 256)
            let b = UInt8((docY * 53 + 89) % 256)
            let a: UInt8 = 255
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let xMod = UInt8((x * 7) % 30)
                pixelData[offset] = r ^ xMod
                pixelData[offset + 1] = g ^ xMod
                pixelData[offset + 2] = b ^ xMod
                pixelData[offset + 3] = a
            }
        }

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: windowHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        return context.makeImage()!
    }

    @Test func stitchesAccuratelyWhenBottomRegionIsUniformWhitespace() {
        let frame1 = makeWhitespaceBottomFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)
        #expect(stitcher.canvas.height == 100)

        // Frame 2 is scrolled down by 35px
        let frame2 = makeWhitespaceBottomFrame(startY: 35)
        let outcome = stitcher.append(frame2)
        #expect(outcome == .appended(shift: 35, newTotalHeight: 135))
        #expect(stitcher.canvas.height == 135)
    }

    @Test func stitchesLargeScrollShiftOverHalfViewport() {
        let frame1 = makePatternFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)

        // Large scroll of 60px on 100px window (60% of viewport)
        let frame2 = makePatternFrame(startY: 60)
        let outcome = stitcher.append(frame2)
        #expect(outcome == .appended(shift: 60, newTotalHeight: 160))
        #expect(stitcher.canvas.height == 160)
    }

    private func makeDarkRepetitiveTextFrame(
        width: Int = 120,
        startY: Int,
        windowHeight: Int = 100,
        cursorState: Int = 0
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixelData = [UInt8](repeating: 0, count: width * windowHeight * 4)

        for y in 0..<windowHeight {
            let docY = startY + y
            let isBulletLine = (docY % 25) < 6
            let blockID = docY / 25
            let lineWidth = 35 + (blockID * 23) % 55

            for x in 0..<width {
                let offset = (y * width + x) * 4
                if isBulletLine && x > 15 && x < 15 + lineWidth {
                    let v = UInt8(180 + ((x * 13 + docY * 7) % 65))
                    pixelData[offset] = v
                    pixelData[offset + 1] = v
                    pixelData[offset + 2] = v
                } else {
                    pixelData[offset] = 9
                    pixelData[offset + 1] = 9
                    pixelData[offset + 2] = 11
                }
                pixelData[offset + 3] = 255
            }
        }

        if cursorState > 0 {
            // 1. Top status/spinner jitter on rows 0..<8 to ensure fullMAD > 4.0 and prevFrameMAD > 4.0,
            // forcing the algorithm to test candidate loop and staticRegion/zeroShift detection
            let spinStep = cursorState % 6
            for ty in 1..<7 {
                let startX = 20 + spinStep * 12
                for tx in startX..<(startX + 10) {
                    guard tx < width - 10 else { break }
                    let off = (ty * width + tx) * 4
                    pixelData[off] = 230
                    pixelData[off + 1] = 180
                    pixelData[off + 2] = 40
                }
            }

            // 2. Local cursor jitter at bottom
            let cursorY = 75 + (cursorState % 5)
            for cy in cursorY..<(cursorY + 8) {
                guard cy < windowHeight else { break }
                for cx in 50..<(50 + 3) {
                    let off = (cy * width + cx) * 4
                    pixelData[off] = 255
                    pixelData[off + 1] = 255
                    pixelData[off + 2] = 255
                }
            }
        }

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: windowHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        return context.makeImage()!
    }

    @Test func doesNotDuplicateWhenScrollingReachesEndOnRepetitiveDarkTextDocument() {
        let frame1 = makeDarkRepetitiveTextFrame(startY: 0)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)
        #expect(stitcher.canvas.height == 100)

        // Valid scroll by 25px
        let frame2 = makeDarkRepetitiveTextFrame(startY: 25)
        let outcome2 = stitcher.append(frame2)
        #expect(outcome2 == .appended(shift: 25, newTotalHeight: 125))
        #expect(stitcher.canvas.height == 125)

        // Reached end of scroll at startY = 25. User scrolls repeatedly at bottom.
        // Blinking cursor, status jitter and dynamic spinner simulate both subtle and large header variations.
        for c in 1...8 {
            let endFrame = makeDarkRepetitiveTextFrame(startY: 25, cursorState: c)
            let outcome = stitcher.append(endFrame)
            #expect(outcome == .unchanged, "End-of-scroll frame with cursor/jitter \(c) should report unchanged")
            #expect(stitcher.canvas.height == 125)
        }
    }

    private func makeFalsePositiveCollisionFrame(
        width: Int = 120,
        windowHeight: Int = 100,
        topPatternSeed: Int,
        stripY: Int
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixelData = [UInt8](repeating: 0, count: width * windowHeight * 4)

        for y in 0..<windowHeight {
            let isStrip = (y >= stripY && y < stripY + 20)
            let localY = y - stripY
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if isStrip {
                    let v = UInt8((x * 13 + localY * 17) % 256)
                    pixelData[offset] = v
                    pixelData[offset + 1] = v ^ 0xAA
                    pixelData[offset + 2] = v ^ 0x55
                } else {
                    let v = UInt8(((x + topPatternSeed * 37) * 11 + y * 19) % 256)
                    pixelData[offset] = v
                    pixelData[offset + 1] = v
                    pixelData[offset + 2] = v
                }
                pixelData[offset + 3] = 255
            }
        }

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: windowHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        return context.makeImage()!
    }

    @Test func rejectsFalsePositiveStripCollisionWhenFullOverlapMismatches() {
        // Frame 1 has strip at bottom (y = 75..<95, matching footerMargin = 5, stripHeight = 20, anchorOffset = 0)
        let frame1 = makeFalsePositiveCollisionFrame(topPatternSeed: 1, stripY: 75)
        var stitcher = LongCaptureStitcher(initialFrame: frame1)
        #expect(stitcher.canvas.height == 100)

        // Frame 2 has matching strip higher up (y = 35..<55, matching bestShift = 40 with minMAD = 0.0),
        // but top 70px region is completely mismatched so Full Overlap Verification must reject it!
        let frame2 = makeFalsePositiveCollisionFrame(topPatternSeed: 2, stripY: 35)
        let outcome = stitcher.append(frame2)
        #expect(outcome == .noOverlap)
        #expect(stitcher.canvas.height == 100)
    }
}
