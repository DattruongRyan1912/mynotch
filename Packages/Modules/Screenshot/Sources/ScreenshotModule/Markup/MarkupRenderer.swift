import CoreGraphics
import CoreText
import Foundation

/// Burns a `MarkupDocument` into its capture at full pixel resolution. Pure, so a host may flatten off the main actor.
nonisolated enum MarkupRenderer {
    /// The capture with its annotations drawn in order at the image's pixel size, or nil if no bitmap could be made.
    /// Annotations are scaled when `document.imageSize` differs from the image's pixel size.
    static func flatten(_ image: CGImage, _ document: MarkupDocument) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = makeContext(width: width, height: height, space: image.colorSpace)
            ?? makeContext(width: width, height: height, space: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let toPixels = document.imageSize.width > 0 && document.imageSize.height > 0
            ? CGAffineTransform(scaleX: CGFloat(width) / document.imageSize.width, y: CGFloat(height) / document.imageSize.height)
            : .identity
        let blockSize = redactBlockSize(for: CGSize(width: width, height: height))
        for annotation in document.annotations {
            if case .redact(let rect) = annotation {
                pixelate(rect.applying(toPixels), blockSize: blockSize, in: context)
            } else {
                context.saveGState()
                context.concatenate(toPixels)
                draw(annotation, in: context)
                context.restoreGState()
            }
        }
        return context.makeImage()
    }

    /// Draws a vector annotation into a context whose user space is image pixels with y down: the flattened bitmap,
    /// or the editor's live preview. Redaction needs the pixels underneath, so only `flatten` performs it.
    static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        switch annotation {
        case .arrow(let start, let tip, let style):
            drawArrow(from: start, to: tip, style: style, in: context)
        case .rectangle(let rect, let style):
            context.setStrokeColor(style.color.cgColor)
            context.setLineJoin(.miter)
            context.stroke(rect.standardized, width: style.width)
        case .text(let string, let origin, let fontSize, let color):
            drawText(string, at: origin, fontSize: fontSize, color: color, in: context)
        case .highlighter(let points, let color, let width):
            guard let first = points.first else { return }
            // Multiply tints the background like ink, keeping text underneath readable.
            context.setBlendMode(.multiply)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: points.count > 1 ? points : [first, first])
            context.strokePath()
        case .redact:
            break
        }
    }

    /// Redaction blocks grow with the capture, so they stay coarse on a 5K screen: max(12, shorter side / 30) pixels.
    static func redactBlockSize(for imageSize: CGSize) -> Int {
        max(12, Int(min(imageSize.width, imageSize.height) / 30))
    }

    private static func makeContext(width: Int, height: Int, space: CGColorSpace?) -> CGContext? {
        guard let space, space.model == .rgb else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func drawArrow(from start: CGPoint, to tip: CGPoint, style: Annotation.StrokeStyle, in context: CGContext) {
        let length = hypot(tip.x - start.x, tip.y - start.y)
        guard length > 0 else { return }
        let direction = CGPoint(x: (tip.x - start.x) / length, y: (tip.y - start.y) / length)
        let headLength = min(max(style.width * 4, 10), length), halfWidth = headLength * 0.55
        let base = CGPoint(x: tip.x - direction.x * headLength, y: tip.y - direction.y * headLength)
        // The shaft ends inside the head, so its round cap never shows past the head's sides or tip.
        let shaftEnd = CGPoint(x: tip.x - direction.x * headLength / 2, y: tip.y - direction.y * headLength / 2)
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)
        context.setLineWidth(style.width)
        context.setLineCap(.round)
        context.strokeLineSegments(between: [start, shaftEnd])
        context.addLines(between: [
            tip,
            CGPoint(x: base.x - direction.y * halfWidth, y: base.y + direction.x * halfWidth),
            CGPoint(x: base.x + direction.y * halfWidth, y: base.y - direction.x * halfWidth),
        ])
        context.closePath()
        context.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: RGBAColor, in context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let ascent = CTFontGetAscent(font), lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        // The text matrix is not part of the graphics state; glyphs are y-up, so flip them for this y-down space.
        let textMatrix = context.textMatrix
        defer { context.textMatrix = textMatrix }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent + CGFloat(index) * lineHeight)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: String(line), attributes: attributes)), context)
        }
    }

    /// Replaces `rect` (pixels, y down, rounded outward to whole pixels) with blocks of its average colour, anchored at
    /// its top-left. Averages are written straight into the bitmap, which stores the top row first, so no original
    /// pixel survives, unlike a light blur, which can be reversed.
    private static func pixelate(_ rect: CGRect, blockSize: Int, in context: CGContext) {
        let region = rect.standardized.integral.intersection(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard !region.isEmpty, let data = context.data else { return }
        context.flush()
        let rowBytes = context.bytesPerRow
        let columnBlocks = blockRanges(Int(region.minX)..<Int(region.maxX), blockSize: blockSize)
        for rows in blockRanges(Int(region.minY)..<Int(region.maxY), blockSize: blockSize) {
            for columns in columnBlocks {
                let rowLength = columns.count * 4
                var sums = (red: 0, green: 0, blue: 0, alpha: 0)
                for y in rows {
                    var pixel = (data + y * rowBytes + columns.lowerBound * 4).assumingMemoryBound(to: UInt8.self)
                    let rowEnd = pixel + rowLength
                    while pixel < rowEnd {
                        sums.red += Int(pixel[0])
                        sums.green += Int(pixel[1])
                        sums.blue += Int(pixel[2])
                        sums.alpha += Int(pixel[3])
                        pixel += 4
                    }
                }
                let count = rows.count * columns.count
                var average = [sums.red, sums.green, sums.blue, sums.alpha].map { UInt8(($0 + count / 2) / count) }
                for y in rows {
                    memset_pattern4(data + y * rowBytes + columns.lowerBound * 4, &average, rowLength)
                }
            }
        }
    }

    /// `range` cut into blocks of `blockSize` from its start. A leftover block narrower than half a block joins the
    /// one before it, so no thin strip or lone corner pixel is left looking like the original.
    private static func blockRanges(_ range: Range<Int>, blockSize: Int) -> [Range<Int>] {
        var blocks = stride(from: range.lowerBound, to: range.upperBound, by: blockSize).map { $0..<min($0 + blockSize, range.upperBound) }
        if blocks.count > 1, let last = blocks.last, last.count * 2 < blockSize {
            blocks.removeLast()
            blocks[blocks.count - 1] = blocks[blocks.count - 1].lowerBound..<last.upperBound
        }
        return blocks
    }
}
