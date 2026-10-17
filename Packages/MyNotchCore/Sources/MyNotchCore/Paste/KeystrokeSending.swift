import CoreGraphics

/// Sends ⌘V to the app with keyboard focus; a protocol so tests never post real key events.
public protocol KeystrokeSending {
    func sendPaste()
}

/// Posts ⌘V through the HID event tap, which needs the Accessibility permission.
public struct CGEventKeystrokeSender: KeystrokeSending {
    /// kVK_ANSI_V is the physical V key, so layouts that move V get a different shortcut (⌘K on Dvorak).
    private static let vKeyCode: CGKeyCode = 9

    public init() {}

    public func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Holds back the user's own key presses while ⌘V is posted, so they cannot mix into the shortcut.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval
        )
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
