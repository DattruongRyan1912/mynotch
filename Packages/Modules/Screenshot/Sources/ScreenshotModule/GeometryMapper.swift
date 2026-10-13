import CoreGraphics

/// Coordinate maths for the selection overlay: AppKit points (origin bottom-left, y up) on one side,
/// CG global points (origin top-left of the primary display, y down) and per-display image pixels on the other.
nonisolated enum GeometryMapper {
    /// AppKit → CG global; `primaryHeight` is the height of the primary display, which anchors both systems.
    static func cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    /// CG global → AppKit; the flip is its own inverse.
    static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    /// The display under an AppKit point. Uses the cursor convention of `NSMouseInRect` (x in [minX, maxX),
    /// y in (minY, maxY]) because `NSEvent.mouseLocation` reports y = maxY on a display's top row.
    static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { display in
            let frame = display.frame
            return point.x >= frame.minX && point.x < frame.maxX && point.y > frame.minY && point.y <= frame.maxY
        }
    }

    /// Limits a selection (AppKit points, any sign) to one display, since a capture never spans displays.
    /// A selection outside the display collapses to an empty rect on its nearest edge.
    static func clamp(_ selection: CGRect, to display: DisplayInfo) -> CGRect {
        let rect = selection.standardized, frame = display.frame
        let minX = rect.minX.clamped(frame.minX, frame.maxX), maxX = rect.maxX.clamped(frame.minX, frame.maxX)
        let minY = rect.minY.clamped(frame.minY, frame.maxY), maxY = rect.maxY.clamped(frame.minY, frame.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The selection (AppKit points) as a crop rect in the display's frozen image: origin at the display's
    /// top-left, y down, in pixels. Rounded outward so partially covered pixels are kept, then kept inside the image.
    static func pixelRect(for selection: CGRect, on display: DisplayInfo) -> CGRect {
        let rect = selection.standardized, frame = display.frame, scale = display.scale
        let width = (frame.width * scale).rounded(), height = (frame.height * scale).rounded()
        let minX = ((rect.minX - frame.minX) * scale).rounded(.down).clamped(0, width)
        let maxX = ((rect.maxX - frame.minX) * scale).rounded(.up).clamped(0, width)
        let minY = ((frame.maxY - rect.maxY) * scale).rounded(.down).clamped(0, height)
        let maxY = ((frame.maxY - rect.minY) * scale).rounded(.up).clamped(0, height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rect spanned by a drag, whichever way the pointer moved.
    static func normalizedSelection(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// `y' = primaryHeight − (y + height)`, mapping either system onto the other.
    private static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

private nonisolated extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
