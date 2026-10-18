import CoreGraphics
import CoreText
import Foundation

/// Burns a `MarkupDocument` into its capture at full pixel resolution. Pure, so a host may flatten off the main actor.
nonisolated enum MarkupRenderer {
    /// The capture with its annotations drawn in order, or nil if no bitmap could be made. The bitmap is the capture's
    /// pixel size plus the padding of the document's canvas, filled as `document.canvasFill` says, with the capture
    /// at the padding's offset, then cut to `document.crop` if there is one. Annotations are scaled when
    /// `document.imageSize` differs from the image's pixel size.
    static func flatten(_ image: CGImage, _ document: MarkupDocument) -> CGImage? {
        let width = image.width, height = image.height
        let hasSize = document.imageSize.width > 0 && document.imageSize.height > 0
        let scaleX = hasSize ? CGFloat(width) / document.imageSize.width : 1
        let scaleY = hasSize ? CGFloat(height) / document.imageSize.height : 1
        let insets = document.canvas
        // Padding in pixels, never more than a capture of this size may grow, whatever scale a damaged file asks for.
        let reach = CGFloat(CanvasInsets.limit(for: CGSize(width: width, height: height)))
        func padding(_ inset: Int, _ scale: CGFloat) -> Int { Int(min((CGFloat(inset) * scale).rounded(.up), reach)) }
        let left = padding(insets.left, scaleX), right = padding(insets.right, scaleX)
        let top = padding(insets.top, scaleY), bottom = padding(insets.bottom, scaleY)
        let canvasWidth = left + width + right, canvasHeight = top + height + bottom
        guard let context = makeContext(width: canvasWidth, height: canvasHeight, space: image.colorSpace)
            ?? makeContext(width: canvasWidth, height: canvasHeight, space: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        // The bitmap's origin is bottom-left here, so the bottom padding is the offset up from it.
        context.draw(image, in: CGRect(x: left, y: bottom, width: width, height: height))
        fillPadding(document.canvasFill, around: PixelRegion(columns: left..<(left + width), rows: top..<(top + height)), in: context)
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
        // Annotation space starts at the capture's top-left corner, which sits at the padding's offset.
        let toPixels = CGAffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: CGFloat(left), ty: CGFloat(top))
        let blockSize = redactBlockSize(for: CGSize(width: width, height: height))
        for (index, annotation) in document.annotations.enumerated() {
            switch annotation {
            case .redact(let rect):
                apply(.pixelate(rect.applying(toPixels)), blockSize: blockSize, in: context)
            case .erase(let rect):
                apply(.erase(rect.applying(toPixels)), blockSize: blockSize, in: context)
            case .magnifier(let center, let radius, let zoom, let style):
                // The lens shows the picture as it ends up: every redaction and erase that comes after it is
                // applied to what it samples, or it would keep an enlarged copy of what they hide.
                let later = document.annotations.dropFirst(index + 1).compactMap { pixelEffect($0, toPixels) }
                // Without a safe source nothing is drawn, rather than a lens that could show hidden pixels.
                guard let source = snapshot(of: context, applying: later, blockSize: blockSize) else { continue }
                magnify(
                    source, center: center.applying(toPixels), radius: radius * scaleX, zoom: zoom,
                    border: style.color, borderWidth: style.width * scaleX, in: context
                )
            default:
                context.saveGState()
                context.concatenate(toPixels)
                draw(annotation, in: context)
                context.restoreGState()
            }
        }
        guard let canvas = context.makeImage() else { return nil }
        // Cut last, so a lens or a redaction near the edge still sees and hides the pixels the crop does not keep.
        guard let crop = document.cropWithinCanvas(insets) else { return canvas }
        return cut(canvas, to: crop, canvasBounds: insets.bounds(of: document.imageSize))
    }

    /// Draws a vector annotation into a context whose user space is image pixels with y down: the flattened bitmap,
    /// or the editor's live draft. Redaction, erasing and the lens need the pixels underneath, so only `flatten` performs them.
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
        case .step(let number, let center, let radius, let color):
            drawStep(number: number, center: center, radius: radius, color: color, in: context)
        case .ruler(let start, let end, let style, let fontSize, let scale):
            drawRuler(from: start, to: end, style: style, fontSize: fontSize, scale: scale, in: context)
        case .redact, .magnifier, .erase:
            break
        }
    }

    /// Redaction blocks grow with the capture, so they stay coarse on a 5K screen: max(12, shorter side / 30) pixels.
    static func redactBlockSize(for imageSize: CGSize) -> Int {
        max(12, Int(min(imageSize.width, imageSize.height) / 30))
    }

    static func makeContext(width: Int, height: Int, space: CGColorSpace?) -> CGContext? {
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

    /// The size of `string` as `draw` lays it out: the widest line by the height of all its lines.
    static func textSize(_ string: String, fontSize: CGFloat) -> CGSize {
        let font = textFont(fontSize)
        let lines = string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let widest = lines.map { line in
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: String(line), attributes: textAttributes(font, .black))), nil, nil, nil)
        }.max() ?? 0
        return CGSize(width: widest, height: CGFloat(lines.count) * lineHeight(of: font))
    }

    static func textFont(_ fontSize: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    }

    private static func lineHeight(of font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    static func textAttributes(_ font: CTFont, _ color: RGBAColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: RGBAColor, in context: CGContext) {
        let font = textFont(fontSize)
        let attributes = textAttributes(font, color)
        let ascent = CTFontGetAscent(font), lineHeight = lineHeight(of: font)
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
    static func pixelate(_ rect: CGRect, blockSize: Int, in context: CGContext) {
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
