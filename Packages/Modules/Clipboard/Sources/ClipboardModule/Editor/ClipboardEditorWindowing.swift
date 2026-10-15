import SwiftUI

/// The editor windows, as the module sees them: a protocol so tests never create a real one. There is one window per item being
/// edited.
protocol ClipboardEditorWindowing: AnyObject {
    /// Opens the window for `model.itemID` with `content`. `onClose` runs once when it closes, whoever closes it. The window asks
    /// `model` whether the close button may close it.
    func show(_ content: AnyView, model: ClipboardEditorModel, onClose: @escaping () -> Void)
    func bringToFront(itemID: UUID)
    /// Closes the window without asking anything.
    func close(itemID: UUID)
}
