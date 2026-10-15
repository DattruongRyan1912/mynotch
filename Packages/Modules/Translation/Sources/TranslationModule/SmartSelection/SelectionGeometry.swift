import CoreGraphics

/// A display in AppKit's coordinates, where y grows upward and the main display's bottom left is the origin.
nonisolated struct ScreenArea: Equatable, Sendable {
    var frame: CGRect
    /// Without the menu bar and the Dock.
    var visibleFrame: CGRect
}

/// Where a selection is and where the chip goes beside it. Accessibility counts from the top left of the main display and
/// down; AppKit from its bottom left and up; both span every display, so one flip about the main display's height maps
/// either to the other.
nonisolated enum SelectionGeometry {
    /// Between the selection and the chip, in points.
    static let gap: CGFloat = 6

    static func cocoaRect(fromAccessibility rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryHeight - rect.origin.y - rect.size.height, width: rect.size.width, height: rect.size.height)
    }

    /// The selection's rectangle in AppKit's coordinates, or the pointer as an empty rectangle when the app gave none that
    /// can be trusted: not finite, with no area, or on no display. The main display is the first of `screens`.
    static func anchor(bounds: CGRect?, pointer: CGPoint, screens: [ScreenArea]) -> CGRect {
        let fallback = CGRect(origin: pointer, size: .zero)
        guard let bounds, let main = screens.first, isUsable(bounds) else { return fallback }
        let rect = cocoaRect(fromAccessibility: bounds, primaryHeight: main.frame.height)
        return screens.contains { $0.frame.intersects(rect) } ? rect : fallback
    }

    /// The chip centred just below the anchor, above it when there is no room below, always inside the visible frame of the
    /// display the anchor is on.
    static func chipFrame(size: CGSize, anchor: CGRect, screens: [ScreenArea]) -> CGRect {
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - gap - size.height
        guard let visible = screen(for: anchor, in: screens)?.visibleFrame else { return CGRect(origin: CGPoint(x: x, y: y), size: size) }
        if y < visible.minY { y = anchor.maxY + gap }
        x = clamp(x, visible.minX, visible.maxX - size.width)
        y = clamp(y, visible.minY, visible.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width > 0 && rect.size.height > 0
    }

    /// The display holding the anchor's centre (at distance 0, edges included), else the nearest one.
    private static func screen(for anchor: CGRect, in screens: [ScreenArea]) -> ScreenArea? {
        let centre = CGPoint(x: anchor.midX, y: anchor.midY)
        return screens.min { distance(from: centre, to: $0.frame) < distance(from: centre, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        hypot(max(frame.minX - point.x, 0, point.x - frame.maxX), max(frame.minY - point.y, 0, point.y - frame.maxY))
    }

    /// `value` within `low...high`; `low` wins when the range is empty (a chip wider than the display).
    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}
