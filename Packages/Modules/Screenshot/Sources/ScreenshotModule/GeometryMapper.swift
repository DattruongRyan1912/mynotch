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
    /// Edges within rounding noise of a pixel boundary count as on it, so a snapped selection crops exactly its pixels.
    static func pixelRect(for selection: CGRect, on display: DisplayInfo) -> CGRect {
        let rect = selection.standardized, frame = display.frame, scale = display.scale
        let width = (frame.width * scale).rounded(), height = (frame.height * scale).rounded()
        let minX = ((rect.minX - frame.minX) * scale).rounded(.down, tolerance: pixelTolerance).clamped(0, width)
        let maxX = ((rect.maxX - frame.minX) * scale).rounded(.up, tolerance: pixelTolerance).clamped(0, width)
        let minY = ((frame.maxY - rect.maxY) * scale).rounded(.down, tolerance: pixelTolerance).clamped(0, height)
        let maxY = ((frame.maxY - rect.minY) * scale).rounded(.up, tolerance: pixelTolerance).clamped(0, height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The selection with every edge moved to the nearest pixel of the display's frozen image. The overlay draws
    /// this rect and crops `pixelRect(for:on:)` of it, so no dimmed sliver ends up in the capture.
    static func snapped(_ selection: CGRect, to display: DisplayInfo) -> CGRect {
        let rect = selection.standardized, frame = display.frame, scale = display.scale
        func fromLeft(_ x: CGFloat) -> CGFloat { frame.minX + ((x - frame.minX) * scale).rounded() / scale }
        // Image rows count from the top, so y snaps relative to the display's top edge.
        func fromTop(_ y: CGFloat) -> CGFloat { frame.maxY - ((frame.maxY - y) * scale).rounded() / scale }
        let minX = fromLeft(rect.minX), maxX = fromLeft(rect.maxX)
        let minY = fromTop(rect.minY), maxY = fromTop(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The height of the primary display, the one at the origin, which anchors the flip between AppKit and CG.
    static func primaryHeight(of displays: [DisplayInfo]) -> CGFloat? {
        displays.first { $0.frame.origin == .zero }?.frame.height
    }

    /// The display under the centre of a window's bounds (CG global points): the best guess for the display
    /// a window straddling two belongs to.
    static func display(containingCenterOf cgRect: CGRect, in displays: [DisplayInfo], primaryHeight: CGFloat) -> DisplayInfo? {
        let center = appKitRect(fromCG: cgRect, primaryHeight: primaryHeight)
        return display(containing: CGPoint(x: center.midX, y: center.midY), in: displays)
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

/// Pixel positions computed through a division by the scale and back can miss a whole number by a few ULPs.
private nonisolated let pixelTolerance: CGFloat = 1e-6

private nonisolated extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }

    /// Rounds by `rule`, except that a value within `tolerance` of a whole number becomes that number.
    func rounded(_ rule: FloatingPointRoundingRule, tolerance: CGFloat) -> CGFloat {
        let nearest = rounded()
        return Swift.abs(self - nearest) <= tolerance ? nearest : rounded(rule)
    }
}
