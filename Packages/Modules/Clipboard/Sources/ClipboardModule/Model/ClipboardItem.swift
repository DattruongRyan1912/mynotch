import Foundation

/// One captured copy. `contentHash` identifies duplicates, so re-copying moves the item instead of adding one.
nonisolated struct ClipboardItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var content: ClipboardContent
    var contentHash: String
    var copiedAt: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    /// Whether a text is code, and in which language, decided when it was copied. nil for other kinds, and for a text
    /// saved before this existed until the module has looked at it, a batch at a time, after it starts.
    var codeDetection: CodeDetection?

    /// The language of a text that is code.
    var codeLanguage: CodeLanguage? { codeDetection?.language }
    var isCode: Bool { codeLanguage != nil }
}

/// A named collection of pinned items; items in any board are never pruned.
nonisolated struct ClipboardBoard: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var systemImage: String
    /// Newest pin first.
    var itemIDs: [UUID]
}
