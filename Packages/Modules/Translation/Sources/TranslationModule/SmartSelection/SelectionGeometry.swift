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
    /// A selection taller than about three chips is a block of text; the chip belongs where the drag ended, not under it.
    static let tallSelection: CGFloat = 96
    /// How far from the selection's rectangle the pointer may be for the rectangle to be believed.
    static let pointerTolerance: CGFloat = 60

    static func cocoaRect(fromAccessibility rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryHeight - rect.origin.y - rect.size.height, width: rect.size.width, height: rect.size.height)
    }

    /// The selection's rectangle in AppKit's coordinates, or the pointer as an empty rectangle when the app gave none that
    /// can be trusted: not finite, with no area, or on no display. The main display is the first of `screens`.
    ///
    /// - Parameter pointerMatters: the pointer made the selection, so it is where the selection is: a rectangle far from it
    ///   (some apps answer with one at the corner of the display whatever is selected) is not believed, and a rectangle of a
    ///   whole block of text is replaced by the pointer. A keyboard selection has no pointer to go by.
    static func anchor(bounds: CGRect?, pointer: CGPoint, screens: [ScreenArea], pointerMatters: Bool = false) -> CGRect {
        let fallback = CGRect(origin: pointer, size: .zero)
        guard let bounds, let main = screens.first, isUsable(bounds) else { return fallback }
        let rect = cocoaRect(fromAccessibility: bounds, primaryHeight: main.frame.height)
        guard screens.contains(where: { $0.frame.intersects(rect) }) else { return fallback }
        if pointerMatters {
            guard rect.insetBy(dx: -pointerTolerance, dy: -pointerTolerance).contains(pointer), rect.height <= tallSelection else {
                return fallback
            }
        }
        return rect
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
