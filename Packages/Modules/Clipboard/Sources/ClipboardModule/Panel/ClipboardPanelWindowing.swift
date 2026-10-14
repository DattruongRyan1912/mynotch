import CoreGraphics
import SwiftUI

/// The floating panel's window, as the module sees it: a protocol so tests never create a real window.
protocol ClipboardPanelWindowing: AnyObject {
    var isOpen: Bool { get }
    /// The panel has the keyboard.
    var isKey: Bool { get }
    /// The bottom left corner of the panel's frame while it is open.
    var origin: CGPoint? { get }
    /// Opens the panel with `content`, over the app in front and without activating MyNotch: at `restoringOrigin` when
    /// it still fits on a screen, else beside the pointer. The window reports the model what happens to it (the
    /// keyboard leaving, a click elsewhere, ⌘1 to ⌘9, a drag). `onClose` runs once when it closes, whoever closes it.
    func show(_ content: AnyView, model: ClipboardPanelModel, restoringOrigin: CGPoint?, onClose: @escaping () -> Void)
    /// Gives the keyboard back to the panel, e.g. for a pinned one that handed it to the app behind.
    func focus()
    /// Lets the app behind the panel take the keyboard while the panel stays on screen.
    func returnKeyboard()
    func close()
}
