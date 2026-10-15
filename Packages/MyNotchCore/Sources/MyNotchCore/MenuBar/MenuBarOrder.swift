import CoreGraphics

/// Whether the two status items are where `MenuBarHider` needs them, judged from their windows' frames (screen
/// coordinates). Pure, because it is the only thing standing between collapsing and hiding the way back.
nonisolated public enum MenuBarOrder {
    /// "‹" is on the same menu bar as the MyNotch icon and ends before the icon's middle, with its own middle and start before
    /// the icon's too. Frames that coincide, overlap past the middle, sit on different displays, have no area or are not on any
    /// bar (parked off the edge, dropped, below the bar) all fail: collapsing then could push the icon off the screen too.
    public static func isLeftOf(separator: CGRect, toggle: CGRect, screens: [MenuBarScreen]) -> Bool {
        guard let first = screenIndex(of: separator, in: screens), first == screenIndex(of: toggle, in: screens) else { return false }
        return separator.minX < toggle.minX && separator.midX < toggle.midX && separator.maxX <= toggle.midX
    }

    /// The icon is on a menu bar, so it can be clicked. While everything is collapsed this is what still has to hold: an icon
    /// the separator pushed off the screen (it was dragged to the separator's left) or the system dropped is not.
    public static func isReachable(toggle: CGRect, screens: [MenuBarScreen]) -> Bool {
        screenIndex(of: toggle, in: screens) != nil
    }

    /// The first display whose bar the frame is on: its centre inside the display's width and its height touching the bar.
    private static func screenIndex(of frame: CGRect, in screens: [MenuBarScreen]) -> Int? {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
        return screens.firstIndex { screen in
            let display = screen.frame
            return frame.midX >= display.minX && frame.midX < display.maxX
                && frame.minY < display.maxY && frame.maxY > display.maxY - screen.barHeight
        }
    }
}
