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
    /// true when the app that copied it marked it as a secret (a password manager's password or code), which only matters
    /// when the user chose to keep such copies. nil otherwise, and for items saved before this existed.
    var sensitive: Bool?

    /// The language of a text that is code.
    var codeLanguage: CodeLanguage? { codeDetection?.language }
    var isCode: Bool { codeLanguage != nil }
    var isSensitive: Bool { sensitive == true }
}

/// A named collection of pinned items; items in any board are never pruned. Boards are listed in the order of
/// `ClipboardHistory.boards`, which is the order the user gave them.
nonisolated struct ClipboardBoard: Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    /// An SF Symbol name.
    var systemImage: String
    var color: ClipboardBoardColor = .accent
    /// Newest pin first.
    var itemIDs: [UUID]
}

/// In an extension so the memberwise initializer stays available. The colour is left out of the file while it is the
/// accent, so a board nobody coloured is stored as it always was, and a file from before colours still reads: a missing,
/// unknown or odd colour is the accent.
nonisolated extension ClipboardBoard: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, systemImage, color, itemIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        systemImage = try container.decode(String.self, forKey: .systemImage)
        color = (try? container.decodeIfPresent(String.self, forKey: .color)).flatMap { ClipboardBoardColor(rawValue: $0) } ?? .accent
        itemIDs = try container.decode([UUID].self, forKey: .itemIDs)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(systemImage, forKey: .systemImage)
        if color != .accent { try container.encode(color, forKey: .color) }
        try container.encode(itemIDs, forKey: .itemIDs)
    }
}
