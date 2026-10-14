import SwiftUI

/// The library's window, as the module sees it: a protocol so tests never create a real window.
protocol ClipboardLibraryWindowing: AnyObject {
    var isOpen: Bool { get }
    /// The library window has the keyboard.
    var isFrontmost: Bool { get }
    /// Opens the window with `content`. `onClose` runs once when it closes, whoever closes it.
    func show(_ content: AnyView, onClose: @escaping () -> Void)
    func bringToFront()
    /// Lets the app behind the window take the keyboard, before a ⌘V that should reach it.
    func yieldKeyboardFocus()
    func close()
}

extension ClipboardModule: ClipboardLibraryActions {}
