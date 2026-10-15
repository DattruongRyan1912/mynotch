import CoreGraphics

/// One display's menu bar: the display's frame in AppKit screen coordinates (origin bottom left) and how tall its bar is,
/// which differs between a display with a notch and one without.
nonisolated public struct MenuBarScreen: Equatable, Sendable {
    public let frame: CGRect
    public let barHeight: CGFloat

    public init(frame: CGRect, barHeight: CGFloat) {
        self.frame = frame
        self.barHeight = barHeight
    }
}

/// Where the menu bars are, for the "reveal on hover" setting.
nonisolated public enum MenuBarZone {
    /// Whether `point` (AppKit screen coordinates) is on the menu bar of any display. The top edge counts although
    /// `CGRect.contains` leaves it out, because the pointer pushed against the top of the screen sits exactly there.
    public static func contains(_ point: CGPoint, in screens: [MenuBarScreen]) -> Bool {
        screens.contains { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x < frame.maxX
                && point.y >= frame.maxY - screen.barHeight && point.y <= frame.maxY
        }
    }
}
