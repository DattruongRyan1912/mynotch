import AppKit

/// The screen facts geometry needs, decoupled from `NSScreen` for testing.
nonisolated public struct ScreenDescriptor: Equatable, Sendable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeftWidth: CGFloat?
    public var auxiliaryTopRightWidth: CGFloat?
    public var menuBarHeight: CGFloat

    public init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeftWidth: CGFloat?, auxiliaryTopRightWidth: CGFloat?, menuBarHeight: CGFloat) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.menuBarHeight = menuBarHeight
    }
}

extension ScreenDescriptor {
    public init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            // Auto-hidden menu bars report 0; fall back to the standard height.
            menuBarHeight: max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        )
    }
}
