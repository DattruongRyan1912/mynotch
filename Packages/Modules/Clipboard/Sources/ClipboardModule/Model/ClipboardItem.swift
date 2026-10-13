import Foundation

/// One captured copy. `contentHash` identifies duplicates, so re-copying moves the item instead of adding one.
nonisolated struct ClipboardItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var content: ClipboardContent
    var contentHash: String
    var copiedAt: Date
    var sourceBundleID: String?
    var sourceAppName: String?
}

/// A named collection of pinned items; items in any board are never pruned.
nonisolated struct ClipboardBoard: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var systemImage: String
    /// Newest pin first.
    var itemIDs: [UUID]
}
