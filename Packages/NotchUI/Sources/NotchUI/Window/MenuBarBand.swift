import AppKit

/// What the black menu bar needs to know about one display.
nonisolated struct MenuBarBandScreen: Equatable, Sendable {
    var id: CGDirectDisplayID
    /// In AppKit's global coordinates.
    var frame: CGRect
    /// How much of the top the menu bar takes. 0 while it is auto-hidden, and on a display that has none (a second display when the
    /// displays do not have separate Spaces). `ScreenDescriptor.menuBarHeight` is not this: it falls back to 24 for the notch's sake.
    var menuBarHeight: CGFloat
    var hasHardwareNotch: Bool
}

extension MenuBarBandScreen {
    init?(_ screen: NSScreen) {
        guard let id = screen.displayID else { return nil }
        self.init(
            id: id, frame: screen.frame, menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            hasHardwareNotch: NotchGeometry(screen: ScreenDescriptor(screen), config: NotchLayoutConfig()).kind == .hardware
        )
    }
}

/// Where the black menu bar is, as pure rules over the displays' facts.
nonisolated enum MenuBarBand {
    /// The menu bar's own rectangle: the screen's full width, `menuBarHeight` down from its top edge. nil when the menu bar takes no room.
    static func frame(screenFrame: CGRect, menuBarHeight: CGFloat) -> CGRect? {
        guard menuBarHeight > 0 else { return nil }
        return CGRect(x: screenFrame.minX, y: screenFrame.maxY - menuBarHeight, width: screenFrame.width, height: menuBarHeight)
    }

    /// The band of each display that is to have one now. None on a display covered by a fullscreen window, and none while its menu
    /// bar is hidden: a band there would be drawn over the top of the apps' windows, which reach the top edge then.
    static func plan(mode: BlackMenuBar, screens: [MenuBarBandScreen], fullscreen: Set<CGDirectDisplayID>) -> [CGDirectDisplayID: CGRect] {
        guard mode != .off else { return [:] }
        var plan: [CGDirectDisplayID: CGRect] = [:]
        for screen in screens where !fullscreen.contains(screen.id) && (mode == .allScreens || screen.hasHardwareNotch) {
            plan[screen.id] = frame(screenFrame: screen.frame, menuBarHeight: screen.menuBarHeight)
        }
        return plan
    }
}
