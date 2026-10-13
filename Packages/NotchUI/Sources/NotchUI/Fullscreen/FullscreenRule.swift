import CoreGraphics

/// One on-screen window, as reported by `CGWindowListCopyWindowInfo` (global top-left coordinates).
nonisolated public struct WindowInfo: Equatable, Sendable {
    public var ownerPID: pid_t
    public var layer: Int
    public var bounds: CGRect

    public init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }
}

nonisolated public enum FullscreenRule {
    /// True when the frontmost app has a normal-layer window covering the whole display.
    public static func isFullscreen(windows: [WindowInfo], frontmostPID: pid_t, displayBounds: CGRect) -> Bool {
        windows.contains { window in
            window.ownerPID == frontmostPID
                && window.layer == 0
                && abs(window.bounds.minX - displayBounds.minX) <= 1
                && abs(window.bounds.minY - displayBounds.minY) <= 1
                && abs(window.bounds.width - displayBounds.width) <= 1
                && abs(window.bounds.height - displayBounds.height) <= 1
        }
    }
}
