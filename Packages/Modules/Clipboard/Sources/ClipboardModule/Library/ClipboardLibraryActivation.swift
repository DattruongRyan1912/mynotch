import AppKit

/// Decides the app's activation policy when the library window closes. The library makes MyNotch a regular app (Dock
/// icon, menu bar, ⌘Tab) so its window can take typing; Settings and other modules' windows do the same, so going back
/// to a menu bar app must wait for the last of them.
nonisolated enum ClipboardLibraryActivation {
    /// What the decision needs to know about one window.
    struct WindowState: Equatable {
        var id: ObjectIdentifier
        var isVisible: Bool
        var isMiniaturized: Bool
        var isTitled: Bool
    }

    /// `.accessory` unless another titled window is shown or minimized: the Dock is the way back to a minimized one.
    static func policyAfterClosing(_ closing: ObjectIdentifier, among windows: [WindowState]) -> NSApplication.ActivationPolicy {
        windows.contains { $0.id != closing && ($0.isVisible || $0.isMiniaturized) && $0.isTitled } ? .regular : .accessory
    }

    @MainActor static func policyAfterClosing(_ window: NSWindow) -> NSApplication.ActivationPolicy {
        policyAfterClosing(ObjectIdentifier(window), among: NSApp.windows.map {
            WindowState(id: ObjectIdentifier($0), isVisible: $0.isVisible, isMiniaturized: $0.isMiniaturized, isTitled: $0.styleMask.contains(.titled))
        })
    }
}
