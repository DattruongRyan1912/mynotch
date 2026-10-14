import AppKit

/// Invisible 1 pt panel that only takes key status from the notch panel and leaves again. A key window that leaves the
/// screen returns the keyboard to the app in front; doing it with this panel keeps the notch panel itself on screen.
final class KeySinkPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
