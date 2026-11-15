import SwiftUI

/// The preview's window, as the module sees it: a protocol so tests never create a real one.
protocol ClipboardPreviewWindowing: AnyObject {
    var isOpen: Bool { get }
    /// Shows `content` over `hostFrame`'s display (the library window's or the floating panel's), without taking the keyboard
    /// or making MyNotch the active app. `onOutsideClick` runs when the user clicks anywhere but the preview, or the
    /// application loses the front: the host closes the preview then. A click that lands on `hostWindow` itself is swallowed,
    /// so it does not also press the row or card under it; a click in any other window goes on to it.
    func show(_ content: AnyView, hostFrame: CGRect?, hostWindow: ObjectIdentifier?, onOutsideClick: @escaping () -> Void)
    func close()
}
