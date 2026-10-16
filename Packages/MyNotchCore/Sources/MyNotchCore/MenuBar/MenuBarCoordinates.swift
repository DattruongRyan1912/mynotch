import CoreGraphics

/// Accessibility reports positions with the origin at the top left of the primary display and y growing downwards; AppKit's
/// screen coordinates (and so every `MenuBarScreen`) have it at the bottom left of that display and y growing upwards. Both
/// are global, so a display above or left of the primary one has a negative y or x in the first and a y above the primary's
/// height or a negative x in the second.
nonisolated public enum MenuBarCoordinates {
    /// `frame` as Accessibility (and the window server's window list) gives it, in AppKit's coordinates.
    /// `primaryHeight` is the height of the display that has the menu bar, `NSScreen.screens.first`.
    public static func appKitFrame(fromAccessibility frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The way back, for matching an item with its window in the window server's list.
    public static func accessibilityFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
