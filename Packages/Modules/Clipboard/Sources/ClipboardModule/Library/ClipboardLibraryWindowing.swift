import SwiftUI

/// The library's window, as the module sees it: a protocol so tests never create a real window.
protocol ClipboardLibraryWindowing: AnyObject {
    var isOpen: Bool { get }
    /// The library window has the keyboard.
    var isFrontmost: Bool { get }
    /// The window's frame while it is open, which tells the large preview which display to appear on.
    var frame: CGRect? { get }
    /// Which window the library is, for the preview to know whose clicks to swallow.
    var windowIdentity: ObjectIdentifier? { get }
    /// Opens the window with `content`. The window asks `model` what the large preview makes of a key press. `onClose` runs once
    /// when it closes, whoever closes it.
    func show(_ content: AnyView, model: ClipboardLibraryModel, onClose: @escaping () -> Void)
    func bringToFront()
    /// Lets the app behind the window take the keyboard, before a ⌘V that should reach it.
    func yieldKeyboardFocus()
    func close()
}

extension ClipboardModule: ClipboardLibraryActions {}
