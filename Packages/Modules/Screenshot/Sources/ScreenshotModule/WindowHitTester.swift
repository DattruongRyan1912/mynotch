import CoreGraphics

/// Picks the window that window mode highlights under the pointer.
nonisolated enum WindowHitTester {
    /// The frontmost normal-layer window of another app containing `cgPoint` (CG global). `windows` must be in
    /// front-to-back order; menus, the Dock and MyNotch's own panels are skipped, as are slivers below `minimumSize`.
    static func window(at cgPoint: CGPoint, in windows: [CapturableWindow], excludingPID: pid_t, minimumSize: CGFloat = 20) -> CapturableWindow? {
        windows.first { window in
            window.layer == 0 && window.ownerPID != excludingPID
                && window.bounds.width >= minimumSize && window.bounds.height >= minimumSize
                && window.bounds.contains(cgPoint)
        }
    }
}
