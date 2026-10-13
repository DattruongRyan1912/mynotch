import Foundation
import UniformTypeIdentifiers

/// One thing on the shelf. Files are kept as bookmarks, so they are found again after being moved or renamed.
nonisolated struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case file(bookmark: Data, name: String, utType: UTType)
        case text(String)
        case link(URL)

        /// The app is not sandboxed, so a plain bookmark needs no security scope.
        static func file(at url: URL) throws -> Kind {
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            return .file(bookmark: try url.bookmarkData(), name: url.lastPathComponent, utType: type)
        }
    }

    let id: UUID
    let kind: Kind
    let addedAt: Date

    init(id: UUID = UUID(), kind: Kind, addedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.addedAt = addedAt
    }
}
