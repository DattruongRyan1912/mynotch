import CoreGraphics

/// One display's menu bar: the display's frame in AppKit screen coordinates (origin bottom left) and how tall its bar is,
/// which differs between a display with a notch and one without.
nonisolated public struct MenuBarScreen: Equatable, Sendable {
    public let frame: CGRect
    public let barHeight: CGFloat
    /// The stretch of the display's width the notch covers, in the same x coordinates as `frame`; nil without a notch. macOS draws
    /// no status item there, so nothing in it can be seen or clicked.
    public let notchGap: ClosedRange<CGFloat>?

    public init(frame: CGRect, barHeight: CGFloat, notchGap: ClosedRange<CGFloat>? = nil) {
        self.frame = frame
        self.barHeight = barHeight
        self.notchGap = notchGap
    }

    /// The notch's gap from the widths of the two areas beside it (`auxiliaryTopLeftArea`, `auxiliaryTopRightArea`), which are the
    /// same on every display whatever the coordinates of the areas themselves. Nil when either is missing or they leave no gap.
    public static func notchGap(frame: CGRect, leftWidth: CGFloat?, rightWidth: CGFloat?) -> ClosedRange<CGFloat>? {
        guard let leftWidth, let rightWidth, leftWidth > 0, rightWidth > 0 else { return nil }
        let lower = frame.minX + leftWidth
        let upper = frame.maxX - rightWidth
        return lower < upper ? lower...upper : nil
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
