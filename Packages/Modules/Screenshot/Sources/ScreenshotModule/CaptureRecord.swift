import Foundation

/// One capture in the tray, as listed in `captures.json`. The PNG is `fileName` next to the index.
nonisolated struct CaptureRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var fileName: String
    var createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    /// The stored image carries annotations from the markup editor.
    var hasMarkup: Bool
    /// When the editor last replaced the image. The tray reloads a card's thumbnail when its record changes, and
    /// the size and `hasMarkup` stay the same after the first save. nil for a capture never edited, and in older indexes.
    var editedAt: Date?
}
