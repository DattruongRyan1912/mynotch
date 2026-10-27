import CoreGraphics

/// Picks the window that window mode highlights under the pointer.
nonisolated enum WindowHitTester {
    /// Decides whether a window can be selected for capture. Windows of another app at layer 0 are allowed;
    /// windows of MyNotch itself (`excludingPID`) are only allowed if they are normal layer 0 workspace windows with a title
    /// (e.g. Recording Editor, Markup Editor), keeping the notch, HUDs, and panels unselected.
    static func isCapturable(_ window: CapturableWindow, excludingPID: pid_t) -> Bool {
        guard window.layer == 0 else { return false }
        if window.ownerPID == excludingPID {
            guard let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return false
            }
            return true
        }
        return true
    }

    /// The frontmost normal-layer window containing `cgPoint` (CG global). `windows` must be in
    /// front-to-back order; menus, the Dock and MyNotch's own floating panels are skipped, as are slivers below `minimumSize`.
    static func window(at cgPoint: CGPoint, in windows: [CapturableWindow], excludingPID: pid_t, minimumSize: CGFloat = 20) -> CapturableWindow? {
        windows.first { window in
            isCapturable(window, excludingPID: excludingPID)
                && window.bounds.width >= minimumSize && window.bounds.height >= minimumSize
                && window.bounds.contains(cgPoint)
        }
    }
}
