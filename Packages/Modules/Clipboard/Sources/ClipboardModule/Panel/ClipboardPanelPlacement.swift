import CoreGraphics

/// Where the floating panel goes, as pure geometry on the screens' rectangles so no test needs a display. All
/// coordinates are AppKit's: global, with the origin at the bottom left of the main screen and y growing upwards.
nonisolated enum ClipboardPanelPlacement {
    /// What the panel needs to know of a screen: the whole frame decides which screen has a point, the visible
    /// frame (without the menu bar and the Dock) is where the panel may go.
    struct Screen: Equatable, Sendable {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    static let size = CGSize(width: 660, height: 420)
    /// Between the pointer and the panel's nearest corner.
    static let pointerOffset: CGFloat = 12

    /// Below and to the right of the pointer, on the screen that has the pointer. Near the right edge it opens to the
    /// left of the pointer, near the bottom above it, so the pointer is never under the panel; whatever is left over
    /// is pulled inside the visible frame. The top left corner wins on a screen smaller than the panel, since that is
    /// where the header is.
    static func frame(size: CGSize, pointer: CGPoint, screens: [Screen]) -> CGRect {
        var x = pointer.x + pointerOffset
        var y = pointer.y - pointerOffset - size.height
        guard let area = screen(at: pointer, in: screens)?.visibleFrame else {
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        if x + size.width > area.maxX { x = pointer.x - pointerOffset - size.width }
        if y < area.minY { y = pointer.y + pointerOffset }
        return inside(CGRect(origin: CGPoint(x: x, y: y), size: size), area)
    }

    /// The panel at a position remembered while it was pinned, pulled inside the screen it overlaps most. nil when it
    /// overlaps no screen any more (the display it was on is gone), so the caller opens it at the pointer instead.
    static func restoredFrame(size: CGSize, origin: CGPoint, screens: [Screen]) -> CGRect? {
        let proposed = CGRect(origin: origin, size: size)
        func overlap(_ screen: Screen) -> CGFloat {
            let shared = proposed.intersection(screen.frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 else { return nil }
        return inside(proposed, best.visibleFrame)
    }

    /// The screen whose frame has the point; for a point on none (a stale position) the nearest one.
    private static func screen(at point: CGPoint, in screens: [Screen]) -> Screen? {
        if let containing = screens.first(where: { $0.frame.contains(point) }) { return containing }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(area.minX, min(frame.origin.x, area.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, area.minY), area.maxY - frame.height)
        return frame
    }
}

/// Where a pinned panel was left, as the settings store it: the bottom left corner of its frame.
nonisolated struct ClipboardPanelPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}
