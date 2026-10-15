import CoreGraphics

/// The windows MyNotch put into a zone, so the next one can be put beside them instead of over them. Kept in memory for as
/// long as the module runs, and only trusted while a window is still where it was put: one that was closed, moved or
/// resized since is forgotten the next time it is asked about.
final class PlacedWindows {
    /// A few windows fill a screen; the oldest make room for new ones.
    static let capacity = 8
    /// How far a window may differ from where it was put and still count as being there: apps round sizes and positions.
    static let tolerance: CGFloat = 2

    /// A window that is still where it was put.
    struct Placed {
        let app: SnapApp
        let target: SnapTarget
        /// Where the window is now, in Accessibility coordinates.
        let frame: CGRect
    }

    private struct Entry {
        let window: any SnapWindow
        let app: SnapApp
        let target: SnapTarget
        let frame: CGRect
    }

    private var entries: [Entry] = []

    var count: Int { entries.count }

    /// `window` was put in `target` and is now at `frame` (as it answered afterwards, not as it was asked). A window put
    /// again is remembered only in its new place.
    func record(_ window: any SnapWindow, in target: SnapTarget, frame: CGRect) {
        entries.removeAll { $0.window.isSame(as: window) }
        entries.append(Entry(window: window, app: window.app, target: target, frame: frame))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// The windows other than `window` that are still where they were put. Asking the app is one call per window; the
    /// ones that no longer answer or no longer match are dropped for good.
    func current(excluding window: any SnapWindow) -> [Placed] {
        var found: [Placed] = []
        entries = entries.filter { entry in
            if entry.window.isSame(as: window) { return true }
            guard let live = entry.window.frame(), Self.isStillThere(live, at: entry.frame) else { return false }
            found.append(Placed(app: entry.app, target: entry.target, frame: live))
            return true
        }
        return found
    }

    func removeAll() {
        entries.removeAll()
    }

    private static func isStillThere(_ live: CGRect, at frame: CGRect) -> Bool {
        abs(live.minX - frame.minX) <= tolerance && abs(live.minY - frame.minY) <= tolerance
            && abs(live.width - frame.width) <= tolerance && abs(live.height - frame.height) <= tolerance
    }
}
