import CoreGraphics
import Foundation

/// Stitches vertically scrolling frames into a single continuous long screenshot.
public nonisolated struct LongCaptureStitcher: Sendable {
    public enum StitchOutcome: Equatable, Sendable {
        case appended(shift: Int, newTotalHeight: Int)
        case unchanged
        case noOverlap
        case reachedMaxHeight
    }

    public private(set) var canvas: CGImage
    public let maxCanvasHeight: Int
    public let bottomChromeIgnoreRatio: Double
    public let maxAcceptableMAD: Double
    private var lastFramePixels: [UInt8]?
    private var lastFrameSize: (width: Int, height: Int) = (0, 0)

    public init(
        initialFrame: CGImage,
        maxCanvasHeight: Int = 16_000,
        bottomChromeIgnoreRatio: Double = 0.05,
        maxAcceptableMAD: Double = 18.0
    ) {
        self.canvas = initialFrame
        self.maxCanvasHeight = maxCanvasHeight
        self.bottomChromeIgnoreRatio = bottomChromeIgnoreRatio
        self.maxAcceptableMAD = maxAcceptableMAD
        self.lastFramePixels = Self.extractRGBA(
            from: initialFrame,
            rect: CGRect(x: 0, y: 0, width: initialFrame.width, height: initialFrame.height)
        )
        self.lastFrameSize = (initialFrame.width, initialFrame.height)
    }

    /// Appends the next scrolling frame to the canvas if a valid downward scroll is detected.
    public mutating func append(_ incoming: CGImage) -> StitchOutcome {
        let width = canvas.width
        guard incoming.width == width else { return .noOverlap }
        guard canvas.height < maxCanvasHeight else { return .reachedMaxHeight }

        let footerMargin = min(max(Int(Double(incoming.height) * bottomChromeIgnoreRatio), 4), min(36, incoming.height / 5))
        let stripHeight = min(max(incoming.height / 5, 12), 56)
        let compareHeight = min(canvas.height, incoming.height)
        guard compareHeight > footerMargin + stripHeight else { return .noOverlap }

        let xStart = max(width / 10, 0)
        let xEnd = min(width - width / 10, width)
        guard xEnd > xStart else { return .noOverlap }

        // Extract RGBA of bottom portion of canvas and full incoming frame
        guard let canvasBottomPixels = Self.extractRGBA(
            from: canvas,
            rect: CGRect(x: 0, y: canvas.height - compareHeight, width: width, height: compareHeight)
        ),
        let incomingPixels = Self.extractRGBA(
            from: incoming,
            rect: CGRect(x: 0, y: 0, width: width, height: incoming.height)
        ) else { return .noOverlap }

        // 1. Unchanged check: frame-to-frame delta and full-viewport canvas-to-incoming delta
        let fullCompareSpan = compareHeight - footerMargin
        let fullMAD = computeMAD(
            anchor: canvasBottomPixels,
            anchorStartY: 0,
            anchorHeight: fullCompareSpan,
            incoming: incomingPixels,
            candidateY: 0,
            width: width,
            xStart: xStart,
            xEnd: xEnd
        )

        var prevFrameMAD: Double = Double.greatestFiniteMagnitude
        if let lastFramePixels, lastFrameSize == (width, incoming.height) {
            prevFrameMAD = computeMAD(
                anchor: lastFramePixels,
                anchorStartY: 0,
                anchorHeight: fullCompareSpan,
                incoming: incomingPixels,
                candidateY: 0,
                width: width,
                xStart: xStart,
                xEnd: xEnd
            )
        }

        if fullMAD < 3.5 || prevFrameMAD < 3.5 {
            self.lastFramePixels = incomingPixels
            self.lastFrameSize = (width, incoming.height)
            return .unchanged
        }

        // 2. Select high-contrast anchor strip in lower part of frame
        let maxOffset = min(incoming.height / 3, max(0, compareHeight - footerMargin - stripHeight))
        var bestOffset = 0
        var maxEnergy: Double = -1.0
        let step = max(stripHeight / 2, 4)

        for offset in stride(from: 0, through: maxOffset, by: step) {
            let stripY = compareHeight - footerMargin - offset - stripHeight
            guard stripY >= 0 else { continue }
            let energy = computeVerticalEnergy(
                pixels: canvasBottomPixels,
                startY: stripY,
                height: stripHeight,
                width: width,
                xStart: xStart,
                xEnd: xEnd
            )
            if energy > maxEnergy {
                maxEnergy = energy
                bestOffset = offset
            }
        }

        // Try bestOffset first (highest texture/energy), fallback to 0 (widest scroll reach) if needed
        var candidateOffsets: [Int] = [bestOffset]
        if bestOffset != 0 {
            candidateOffsets.append(0)
        }

        for anchorOffset in candidateOffsets {
            let anchorStartY = compareHeight - footerMargin - anchorOffset - stripHeight
            guard anchorStartY >= 0 else { continue }

            let stripEnergy = computeVerticalEnergy(
                pixels: canvasBottomPixels,
                startY: anchorStartY,
                height: stripHeight,
                width: width,
                xStart: xStart,
                xEnd: xEnd
            )
            guard stripEnergy >= 1.0 else { continue }

            let maxShift = incoming.height - footerMargin - anchorOffset - stripHeight
            guard maxShift >= 1 else { continue }

            // Evaluate shift = 0 directly on strip and lower static region
            let zeroShiftCandidateY = incoming.height - footerMargin - anchorOffset - stripHeight
            let zeroShiftMAD = computeMAD(
                anchor: canvasBottomPixels,
                anchorStartY: anchorStartY,
                anchorHeight: stripHeight,
                incoming: incomingPixels,
                candidateY: zeroShiftCandidateY,
                width: width,
                xStart: xStart,
                xEnd: xEnd
            )

            let staticHeight = min(compareHeight / 2, compareHeight - footerMargin - anchorOffset)
            let staticStartY = (compareHeight - footerMargin - anchorOffset) - staticHeight
            let staticCandidateY = (incoming.height - footerMargin - anchorOffset) - staticHeight
            let staticRegionMAD = computeMAD(
                anchor: canvasBottomPixels,
                anchorStartY: staticStartY,
                anchorHeight: staticHeight,
                incoming: incomingPixels,
                candidateY: staticCandidateY,
                width: width,
                xStart: xStart,
                xEnd: xEnd
            )

            var bestShift = -1
            var minMAD = Double.greatestFiniteMagnitude

            for shift in 1...maxShift {
                let candidateY = (incoming.height - footerMargin - anchorOffset - stripHeight) - shift
                let mad = computeMAD(
                    anchor: canvasBottomPixels,
                    anchorStartY: anchorStartY,
                    anchorHeight: stripHeight,
                    incoming: incomingPixels,
                    candidateY: candidateY,
                    width: width,
                    xStart: xStart,
                    xEnd: xEnd
                )
                if mad < minMAD {
                    minMAD = mad
                    bestShift = shift
                }
            }

            if staticRegionMAD < 3.5 || (zeroShiftMAD < 4.5 && minMAD >= zeroShiftMAD - 0.5) || (zeroShiftMAD < 8.0 && minMAD >= zeroShiftMAD * 0.85) {
                self.lastFramePixels = incomingPixels
                self.lastFrameSize = (width, incoming.height)
                return .unchanged
            }

            if bestShift <= 3 && staticRegionMAD < 4.5 {
                self.lastFramePixels = incomingPixels
                self.lastFrameSize = (width, incoming.height)
                return .unchanged
            }

            let effectiveMaxMAD = min(maxAcceptableMAD, max(4.0, stripEnergy * 0.65))
            guard bestShift > 0, minMAD <= effectiveMaxMAD else {
                continue
            }

            // 3. Full Overlap Verification
            let topIgnore = footerMargin
            let anchorBottomY = compareHeight - footerMargin - anchorOffset
            let incomingMatchBottomY = (incoming.height - footerMargin - anchorOffset) - bestShift
            let overlapHeight = min(anchorBottomY - topIgnore, incomingMatchBottomY - topIgnore)

            if overlapHeight > stripHeight {
                let canvasOverlapStartY = anchorBottomY - overlapHeight
                let incomingOverlapStartY = incomingMatchBottomY - overlapHeight
                let zeroShiftOverlapCandidateY = (incoming.height - footerMargin - anchorOffset) - overlapHeight
                let overlapMAD = computeMAD(
                    anchor: canvasBottomPixels,
                    anchorStartY: canvasOverlapStartY,
                    anchorHeight: overlapHeight,
                    incoming: incomingPixels,
                    candidateY: incomingOverlapStartY,
                    width: width,
                    xStart: xStart,
                    xEnd: xEnd
                )
                let overlapEnergy = computeVerticalEnergy(
                    pixels: canvasBottomPixels,
                    startY: canvasOverlapStartY,
                    height: overlapHeight,
                    width: width,
                    xStart: xStart,
                    xEnd: xEnd
                )
                let zeroShiftOverlapMAD = computeMAD(
                    anchor: canvasBottomPixels,
                    anchorStartY: canvasOverlapStartY,
                    anchorHeight: overlapHeight,
                    incoming: incomingPixels,
                    candidateY: zeroShiftOverlapCandidateY,
                    width: width,
                    xStart: xStart,
                    xEnd: xEnd
                )
                if zeroShiftOverlapMAD < 4.5 && overlapMAD >= zeroShiftOverlapMAD - 0.5 {
                    self.lastFramePixels = incomingPixels
                    self.lastFrameSize = (width, incoming.height)
                    return .unchanged
                }
                let maxOverlapMAD = min(maxAcceptableMAD, max(5.0, overlapEnergy * 0.75))
                if overlapMAD > maxOverlapMAD {
                    continue
                }
            }

            let newHeight = canvas.height + bestShift
            guard newHeight <= maxCanvasHeight else {
                return .reachedMaxHeight
            }

            // Splice canvas top and incoming bottom according to anchorOffset
            let canvasTopHeight = canvas.height - footerMargin - anchorOffset
            let incomingBottomY = (incoming.height - footerMargin - anchorOffset) - bestShift
            let incomingBottomHeight = bestShift + footerMargin + anchorOffset

            guard let canvasTop = canvas.cropping(to: CGRect(x: 0, y: 0, width: width, height: canvasTopHeight)),
                  let incomingBottom = incoming.cropping(to: CGRect(x: 0, y: incomingBottomY, width: width, height: incomingBottomHeight))
            else { return .noOverlap }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return .noOverlap }

            context.draw(canvasTop, in: CGRect(x: 0, y: incomingBottomHeight, width: width, height: canvasTopHeight))
            context.draw(incomingBottom, in: CGRect(x: 0, y: 0, width: width, height: incomingBottomHeight))

            guard let stitched = context.makeImage() else { return .noOverlap }
            self.canvas = stitched
            self.lastFramePixels = incomingPixels
            self.lastFrameSize = (width, incoming.height)
            return .appended(shift: bestShift, newTotalHeight: stitched.height)
        }

        self.lastFramePixels = incomingPixels
        self.lastFrameSize = (width, incoming.height)
        return .noOverlap
    }

    private func computeMAD(
        anchor: [UInt8],
        anchorStartY: Int,
        anchorHeight: Int,
        incoming: [UInt8],
        candidateY: Int,
        width: Int,
        xStart: Int,
        xEnd: Int
    ) -> Double {
        var totalDiff: Double = 0
        var count = 0
        let bytesPerPixel = 4

        for y in 0..<anchorHeight {
            let anchorRowOffset = (anchorStartY + y) * width * bytesPerPixel
            let candidateRowOffset = (candidateY + y) * width * bytesPerPixel
            for x in stride(from: xStart, to: xEnd, by: 2) {
                let aOffset = anchorRowOffset + x * bytesPerPixel
                let cOffset = candidateRowOffset + x * bytesPerPixel

                let rDiff = abs(Int(anchor[aOffset]) - Int(incoming[cOffset]))
                let gDiff = abs(Int(anchor[aOffset + 1]) - Int(incoming[cOffset + 1]))
                let bDiff = abs(Int(anchor[aOffset + 2]) - Int(incoming[cOffset + 2]))

                totalDiff += Double(rDiff + gDiff + bDiff) / 3.0
                count += 1
            }
        }

        guard count > 0 else { return Double.greatestFiniteMagnitude }
        return totalDiff / Double(count)
    }

    private func computeVerticalEnergy(
        pixels: [UInt8],
        startY: Int,
        height: Int,
        width: Int,
        xStart: Int,
        xEnd: Int
    ) -> Double {
        var totalDiff: Double = 0
        var count = 0
        let bytesPerPixel = 4

        for y in 0..<(height - 1) {
            let rowOffset1 = (startY + y) * width * bytesPerPixel
            let rowOffset2 = (startY + y + 1) * width * bytesPerPixel
            for x in stride(from: xStart, to: xEnd, by: 4) {
                let off1 = rowOffset1 + x * bytesPerPixel
                let off2 = rowOffset2 + x * bytesPerPixel

                let rDiff = abs(Int(pixels[off1]) - Int(pixels[off2]))
                let gDiff = abs(Int(pixels[off1 + 1]) - Int(pixels[off2 + 1]))
                let bDiff = abs(Int(pixels[off1 + 2]) - Int(pixels[off2 + 2]))

                totalDiff += Double(rDiff + gDiff + bDiff) / 3.0
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        return totalDiff / Double(count)
    }

    private static func extractRGBA(from image: CGImage, rect: CGRect) -> [UInt8]? {
        guard let cropped = image.cropping(to: rect) else { return nil }
        let width = cropped.width
        let height = cropped.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: width * height * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
