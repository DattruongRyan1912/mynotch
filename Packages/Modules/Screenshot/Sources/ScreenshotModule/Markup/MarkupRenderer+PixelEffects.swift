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

    /// The lens: the bitmap as it is now, scaled by `zoom` around `center` and clipped to the circle, with a border
    /// centred on its edge. Everything is in pixels with y down.
    static func magnify(center: CGPoint, radius: CGFloat, zoom: CGFloat, border: RGBAColor, borderWidth: CGFloat, in context: CGContext) {
        guard radius > 0, zoom > 0, let snapshot = context.makeImage() else { return }
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
        context.draw(snapshot, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.restoreGState()
        context.setStrokeColor(border.cgColor)
        context.setLineWidth(borderWidth)
        context.strokeEllipse(in: circle)
    }
}
