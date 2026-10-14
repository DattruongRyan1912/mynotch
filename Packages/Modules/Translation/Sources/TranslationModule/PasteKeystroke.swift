import CoreGraphics

/// Sends ⌘V to the app with keyboard focus; a protocol so tests never post real key events.
protocol PasteKeystroke {
    func send()
}

/// Posts ⌘V through the HID event tap, which needs the Accessibility permission.
struct CGEventPasteKeystroke: PasteKeystroke {
    /// kVK_ANSI_V is the physical V key, so layouts that move V get a different shortcut (⌘K on Dvorak).
    private static let vKeyCode: CGKeyCode = 9

    func send() {
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
