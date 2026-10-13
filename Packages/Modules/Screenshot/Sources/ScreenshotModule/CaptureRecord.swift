import Foundation

/// One capture in the tray, as listed in `captures.json`. The PNG is `fileName` next to the index.
nonisolated struct CaptureRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var fileName: String
    var createdAt: Date
    var pixelWidth: Int
    var pixelHeight: Int
    /// The markup editor replaced the image with an annotated version.
    var hasMarkup: Bool
}
