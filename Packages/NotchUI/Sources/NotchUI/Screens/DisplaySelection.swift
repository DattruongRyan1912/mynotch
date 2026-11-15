import CoreGraphics

/// Which displays show a notch for a display mode, and which display the pointer is on. Pure, so the choice is tested
/// with made-up displays instead of `NSScreen`.
nonisolated enum DisplaySelection {
    /// The displays that show a notch. `displays` is in the system's order, whose first entry is the main display (the
    /// one with the menu bar); `active` is the display the user is working on (see `ActiveDisplay`). A display that is
    /// no longer there is not active, so the main display takes over.
    static func shown(mode: DisplayMode, displays: [CGDirectDisplayID], active: CGDirectDisplayID?) -> Set<CGDirectDisplayID> {
        let main = displays.first.map { Set([$0]) } ?? []
        return switch mode {
        case .all: Set(displays)
        case .main: main
        case .cursor: active.flatMap { displays.contains($0) ? Set([$0]) : nil } ?? main
        }
    }

    /// The display whose frame holds the pointer at `point` (AppKit coordinates), nil between displays.
    static func display(at point: CGPoint, in frames: [(displayID: CGDirectDisplayID, frame: CGRect)]) -> CGDirectDisplayID? {
        frames.first { $0.frame.containsMouseLocation(point) }?.displayID
    }

    /// The display the app with process `pid` has its front window on: the first of its normal-layer windows in `windows`
    /// (front to back, as the system lists them) and the display that holds most of it. Windows and displays are in the
    /// same global coordinates (`WindowInfo`); nil for an app with no such window or one on no display.
    static func display(
        ofFrontWindowOf pid: pid_t, in windows: [WindowInfo], on displays: [(displayID: CGDirectDisplayID, bounds: CGRect)]
    ) -> CGDirectDisplayID? {
        guard let window = windows.first(where: { $0.ownerPID == pid && $0.layer == 0 }) else { return nil }
        func overlap(_ bounds: CGRect) -> CGFloat {
            let shared = window.bounds.intersection(bounds)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return displays.filter { overlap($0.bounds) > 0 }.max { overlap($0.bounds) < overlap($1.bounds) }?.displayID
    }
}
