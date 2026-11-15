import CoreGraphics

/// The effects that need the pixels already drawn: padding next to the capture's edge, smart erase and the lens.
nonisolated extension MarkupRenderer {
    /// Fills the canvas around `image` (the capture's place in the bitmap) for the padding that growth added.
    static func fillPadding(_ fill: CanvasFill, around image: PixelRegion, in context: CGContext) {
        guard let buffer = PixelBuffer(context), image != buffer.region else { return }
        let color: RawPixel
        switch fill {
        case .transparent:
            return
        case .white:
            color = .white
        case .black:
            color = .black
        case .edgeColor:
            // The capture's outermost pixels, not the padding next to them.
            let ring = EdgeColorSampler.sample(buffer, ring: image, around: image.inset(by: EdgeColorSampler.ringWidth))
            guard let ring else { return }
            color = ring.dominant
        }
        let canvas = buffer.region
        buffer.fill(PixelRegion(columns: canvas.columns, rows: canvas.rows.lowerBound..<image.rows.lowerBound), with: color)
        buffer.fill(PixelRegion(columns: canvas.columns, rows: image.rows.upperBound..<canvas.rows.upperBound), with: color)
        buffer.fill(PixelRegion(columns: canvas.columns.lowerBound..<image.columns.lowerBound, rows: image.rows), with: color)
        buffer.fill(PixelRegion(columns: image.columns.upperBound..<canvas.columns.upperBound, rows: image.rows), with: color)
    }

    /// A redaction or smart erase, with its rectangle in bitmap pixels (y down).
    enum PixelEffect {
        case pixelate(CGRect)
        case erase(CGRect)
    }

    /// `annotation` as a pixel effect with its rectangle moved to bitmap pixels, or nil for any other kind.
    static func pixelEffect(_ annotation: Annotation, _ toPixels: CGAffineTransform) -> PixelEffect? {
        switch annotation {
        case .redact(let rect): .pixelate(rect.applying(toPixels))
        case .erase(let rect): .erase(rect.applying(toPixels))
        default: nil
        }
    }

    static func apply(_ effect: PixelEffect, blockSize: Int, in context: CGContext) {
        switch effect {
        case .pixelate(let rect): pixelate(rect, blockSize: blockSize, in: context)
        case .erase(let rect): erase(rect, blockSize: blockSize, in: context)
        }
    }

    /// The bitmap as it is now with `effects` applied on top, for the lens to sample. The context itself is not
    /// touched when there are effects: they are applied to a copy, since the annotations before them still draw
    /// over the unchanged bitmap. nil when no copy could be made.
    static func snapshot(of context: CGContext, applying effects: [PixelEffect], blockSize: Int) -> CGImage? {
        guard !effects.isEmpty else { return context.makeImage() }
        guard let buffer = PixelBuffer(context), let space = context.colorSpace,
              let copy = makeContext(width: buffer.width, height: buffer.height, space: space),
              let target = PixelBuffer(copy) else { return nil }
        for y in 0..<buffer.height {
            memcpy(target.data + y * target.bytesPerRow, buffer.data + y * buffer.bytesPerRow, buffer.width * 4)
        }
        for effect in effects { apply(effect, blockSize: blockSize, in: copy) }
        return copy.makeImage()
    }

    /// Smart erase of `rect` (pixels, y down): the colour of the ring just outside it when that is one colour,
    /// otherwise the same irreversible pixelation as redaction. The ring is outside so that a rectangle drawn
    /// tight around text does not sample the text itself.
    static func erase(_ rect: CGRect, blockSize: Int, in context: CGContext) {
        guard let buffer = PixelBuffer(context) else { return }
        let region = PixelRegion(rect: rect, within: buffer.width, buffer.height)
        guard !region.isEmpty else { return }
        let ring = EdgeColorSampler.sample(buffer, ring: region.outset(by: EdgeColorSampler.ringWidth), around: region)
        if let ring, ring.isUniform {
            buffer.fill(region, with: ring.dominant)
        } else {
            pixelate(rect, blockSize: blockSize, in: context)
        }
    }

    /// The lens: `source` (the whole bitmap, as the lens should see it) scaled by `zoom` around `center` and clipped to
    /// the circle, with a border centred on its edge. Everything is in pixels with y down.
    static func magnify(_ source: CGImage, center: CGPoint, radius: CGFloat, zoom: CGFloat, border: RGBAColor, borderWidth: CGFloat, in context: CGContext) {
        guard radius > 0, zoom > 0 else { return }
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        context.interpolationQuality = .high
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -center.x, y: -center.y)
        // An image is drawn y up, so flip it back over the y-down canvas.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(source, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.restoreGState()
        context.setStrokeColor(border.cgColor)
        context.setLineWidth(borderWidth)
        context.strokeEllipse(in: circle)
    }
}
