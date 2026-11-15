import AppKit
import NotchUI

/// What the panel's controller asks of AppKit and the system to give the keyboard to the app behind, as a value so a test supplies the
/// answers, and plays what AppKit did on a real machine, without a window moving key status or the app in front changing.
struct ClipboardPanelKeyboard {
    /// The app in front, which the key press that follows is for.
    var frontApp: () -> NSRunningApplication?
    /// Whether `window` has the keyboard.
    var isKey: (NSWindow) -> Bool
    /// Takes key status from `window` and gives it to `front`: true when, as far as AppKit can tell, no window of MyNotch has the keyboard
    /// afterwards and `front` is still in front.
    var handBack: (NSWindow, NSRunningApplication?) -> Bool
    /// The same question when there is nothing to take the keyboard from.
    var isWithFront: (NSRunningApplication?) -> Bool

    /// NotchUI's hand-back, the one the notch uses: a hidden 1 pt panel takes key status and leaves.
    static func system(_ handBack: KeyboardHandBack) -> ClipboardPanelKeyboard {
        ClipboardPanelKeyboard(
            frontApp: { NSWorkspace.shared.frontmostApplication },
            isKey: { $0.isKeyWindow },
            handBack: { handBack.returnKeyboard(from: $0, to: $1) },
            isWithFront: { KeyboardHandBack.keyboardIsWith($0) }
        )
    }
}
