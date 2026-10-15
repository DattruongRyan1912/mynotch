import CoreGraphics

/// The Accessibility attributes of one window that placing it needs, behind a protocol so tests give it the habits of
/// real apps (a smallest size, a fixed size, a size clamped by the display, an app that refuses to move). Coordinates are
/// Accessibility's.
protocol WindowAttributes: AnyObject {
    func position() -> CGPoint?
    func size() -> CGSize?
    /// False when the app refused.
    func setPosition(_ position: CGPoint) -> Bool
    func setSize(_ size: CGSize) -> Bool
    /// The app's `AXEnhancedUserInterface`, which Chrome and other apps turn on when assistive technology is at work, and
    /// then animate or ignore moves made from outside. Nil when the app has none.
    func enhancedUserInterface() -> Bool?
    /// False when the app refused.
    func setEnhancedUserInterface(_ on: Bool) -> Bool
}

/// Puts a window where a placement says, whatever size the app gives it.
enum WindowPlacer {
    /// Size first, then position, then the size again: an app clamps a size to the display the window is on, so a window
    /// that moves to a larger display only gets the size it was asked for once it is there. The position is chosen from the
    /// size the window actually has, so one that keeps a bigger size (a smallest or a fixed size) is put against the edge
    /// of its zone and inside the visible area instead of hanging off the display or under the Dock.
    ///
    /// An app whose enhanced user interface is on animates or ignores a frame change made from outside, so that is switched
    /// off for the placement and back on after it, whichever way the placement ends. An app that has it off, or has none, is
    /// not written to at all, and `AXManualAccessibility` (which does not touch frames) is never touched.
    ///
    /// Every call is a wait for the other app, so an app that refuses to move is not called again, and a size the app did
    /// not take is asked for once more at most.
    @discardableResult
    static func place(_ placement: SnapPlacement, on window: some WindowAttributes) -> SnapOutcome {
        let wasOn = window.enhancedUserInterface() == true
        let paused = wasOn && window.setEnhancedUserInterface(false)
        defer { if paused { _ = window.setEnhancedUserInterface(true) } }
        return SnapOutcome(moved: move(placement, on: window), enhancedUI: wasOn)
    }

    private static func move(_ placement: SnapPlacement, on window: some WindowAttributes) -> Bool {
        let target = placement.frame
        let tookSize = window.setSize(target.size)
        let first = window.size() ?? target.size
        guard window.setPosition(placement.origin(for: first)) else { return false }
        guard tookSize, let moved = window.size(), !moved.isClose(to: target.size) else { return true }
        _ = window.setSize(target.size)
        guard let last = window.size() else { return true }
        let origin = placement.origin(for: last)
        guard let current = window.position(), !current.isClose(to: origin) else { return true }
        return window.setPosition(origin)
    }
}

nonisolated private extension CGPoint {
    func isClose(to other: CGPoint) -> Bool { abs(x - other.x) <= 0.5 && abs(y - other.y) <= 0.5 }
}

nonisolated private extension CGSize {
    func isClose(to other: CGSize) -> Bool { abs(width - other.width) < 1 && abs(height - other.height) < 1 }
}
