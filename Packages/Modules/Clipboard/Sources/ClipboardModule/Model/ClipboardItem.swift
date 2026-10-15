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
    /// Whether the app that copied it marked it as a secret (a password manager's password or code): true or false for a
    /// copy made while MyNotch tracked that, nil for one it did not, which is not known to be either. Only matters when the
    /// user keeps such copies, and for a backup.
    var sensitive: Bool?
    /// true for an item a restore was told to keep whatever the limits say: `prune` neither removes it nor counts it. Ends
    /// when the item is copied or used again, which makes it an ordinary item with a date of now. nil otherwise.
    var exemptFromLimits: Bool?
    /// How many times it was copied, counting the first; nil for one copy. A copy that only moved it to the top is one more, MyNotch
    /// using it again is not.
    var copyCount: Int?
    /// true once the user replaced its words in the editor, which keeps its date and its source; nil otherwise.
    var edited: Bool?

    /// The language of a text that is code.
    var codeLanguage: CodeLanguage? { codeDetection?.language }
    var isCode: Bool { codeLanguage != nil }
    var isSensitive: Bool { sensitive == true }
    var isExemptFromLimits: Bool { exemptFromLimits == true }
    var timesCopied: Int { max(copyCount ?? 1, 1) }
    var isEdited: Bool { edited == true }
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
    /// nil for an ordinary board. Never stored in `boards.json`: a board is locked when it has a vault file (see `ClipboardVaultFile`).
    var lock: ClipboardBoardLock?
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
