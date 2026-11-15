import CoreGraphics

/// One on-screen window, as reported by `CGWindowListCopyWindowInfo` (global top-left coordinates).
nonisolated public struct WindowInfo: Equatable, Sendable {
    public var ownerPID: pid_t
    public var layer: Int
    /// Global CG coordinates: origin at the top-left of the main display, y grows downwards.
    public var bounds: CGRect

    public init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }
}

nonisolated public enum FullscreenRule {
    /// Tolerance when a window covers the whole display.
    static let fullTolerance: CGFloat = 1
    /// Tight tolerance for the frame below the camera housing, so a zoomed window that stops at the
    /// menu bar (one point lower on notched Macs) is not mistaken for fullscreen.
    static let belowNotchTolerance: CGFloat = 0.5

    /// True when another app has a normal-layer window covering the display: either the whole display or,
    /// on displays with a camera housing, everything below `topInset` (where macOS puts native fullscreen
    /// windows). `displayBounds` uses global CG coordinates, like `WindowInfo.bounds`.
    public static func isFullscreen(windows: [WindowInfo], ownPID: pid_t, displayBounds: CGRect, topInset: CGFloat = 0) -> Bool {
        let belowNotch = CGRect(
            x: displayBounds.minX,
            y: displayBounds.minY + topInset,
            width: displayBounds.width,
            height: displayBounds.height - topInset
        )
        return windows.contains { window in
            guard window.ownerPID != ownPID, window.layer == 0 else { return false }
            return matches(window.bounds, displayBounds, tolerance: fullTolerance)
                || (topInset > 0 && matches(window.bounds, belowNotch, tolerance: belowNotchTolerance))
        }
    }

    private static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
