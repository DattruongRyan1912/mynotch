import Foundation

public extension Notification.Name {
    /// Notification request to open the markup image editor for an image from any module (e.g. Clipboard, Shelf).
    /// The notification object can contain a file `URL` or image `Data`.
    static let openMarkupEditorForImage = Notification.Name("io.lucasvu.mynotch.screenshot.openMarkupEditorForImage")
}
