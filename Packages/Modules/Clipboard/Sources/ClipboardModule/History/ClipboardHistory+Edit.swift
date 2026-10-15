import Foundation

/// How the editor's result goes into the history.
nonisolated enum ClipboardEditMode: Equatable, Sendable {
    /// "Lưu thành mục mới": the original stays and the words become a new item on top.
    case saveAsNew
    /// "Thay thế mục này": the original takes the new words and stays where it was, dated as it was.
    case replace
}

/// What an edit did, or why it did nothing. `saved` carries the item that holds the words now.
nonisolated enum ClipboardEditOutcome: Equatable, Sendable {
    case saved(UUID)
    /// The words are the ones the item already has.
    case unchanged
    case blank
    case tooLarge
    /// The item is gone from the history (deleted, or its board locked).
    case missing
    /// The item is pinned to a board that is closed.
    case locked
    /// Only texts and links are edited.
    case notEditable
    /// Replacing would leave two items with the same words, which the history never holds; this is the other one.
    case duplicate(UUID)
    case stopped
}

nonisolated extension ClipboardHistory {
    /// Whether the editor may open on the item: it is in the history, it is a text or a link, and the board it is pinned to, if any,
    /// is not closed. A closed board takes its items out of the history, so the last rule only guards a state the module never makes.
    func canEdit(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return ClipboardEditing.text(of: item) != nil && canPreview(id)
    }

    /// Puts `content`, the classified result of an edit of item `id`, into the history. Never touches a pasteboard.
    /// - `replace`: the item keeps its id (so its pins stay), place, date, source, count and secret flag, takes the words, is looked at
    ///   again for code and is marked edited. Refused when another item already has these words.
    /// - `saveAsNew`: an item with these words made now, from no app, carrying the secret flag of the original and, when the original is in
    ///   a board that has a lock, pinned to it too, so a secret changed stays as private as it was. Words an item already has move that
    ///   item to the top instead, with its own source and count.
    mutating func applyEdit(to id: UUID, content: ClipboardContent, mode: ClipboardEditMode, at date: Date) -> ClipboardEditOutcome {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return .missing }
        guard canPreview(id) else { return .locked }
        let original = items[index]
        guard ClipboardEditing.text(of: original) != nil else { return .notEditable }
        let hash = ClipboardContent.hash(of: content)
        let other = items.first { $0.contentHash == hash && $0.id != id }
        switch mode {
        case .replace:
            if hash == original.contentHash { return .unchanged }
            if let other { return .duplicate(other.id) }
            items[index].content = content
            items[index].contentHash = hash
            items[index].codeDetection = ClipboardCodeDetector.detect(content)
            items[index].edited = true
            return .saved(id)
        case .saveAsNew:
            let protectedBoards = boards(containing: id).filter(\.isProtected).map(\.id)
            let savedID: UUID
            if let existing = items.first(where: { $0.contentHash == hash }) {
                touch(id: existing.id, at: date)
                savedID = existing.id
            } else {
                savedID = add(content, hash: hash, source: (nil, nil), at: date, isSensitive: original.isSensitive).id
            }
            for board in protectedBoards { pin(itemID: savedID, to: board) }
            return .saved(savedID)
        }
    }
}
