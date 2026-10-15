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
}
