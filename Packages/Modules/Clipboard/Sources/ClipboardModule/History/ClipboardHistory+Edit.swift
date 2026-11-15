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
    /// - `replace`: the item keeps its id (so its pins stay), source, count and secret flag, takes the words, is looked at again for
    ///   code, is marked edited, and is dated now and put on top like any item that is used (an edit would otherwise leave it in the
    ///   middle with an old date, to be pruned by it). Refused when another item already has these words.
    /// - `saveAsNew`: an item with these words made now, from no app, carrying the secret flag of the original and, when the original is
    ///   in a board that has a lock, pinned to it too, so a secret changed stays as private as it was. Words an item already has move
    ///   that item to the top instead, with its own source and count, and never pin it anywhere: when the original is in a board that
    ///   has a lock and that item is not in all of those boards, the save is refused (`duplicate`), since pinning it would take an
    ///   ordinary item out of the history at the next lock, or an item of another locked board out of that one.
    ///
    /// `originalWasSensitive` is what the editor remembers of an original that has since left the history (pruned, deleted, cleared):
    /// its words can still be saved as a new item, which pins nothing and carries that flag. nil for an original that is not known to
    /// have been an ordinary item, so a missing one is `missing`.
    mutating func applyEdit(
        to id: UUID, content: ClipboardContent, mode: ClipboardEditMode, at date: Date, originalWasSensitive: Bool? = nil
    ) -> ClipboardEditOutcome {
        let hash = ClipboardContent.hash(of: content)
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            guard mode == .saveAsNew, let originalWasSensitive else { return .missing }
            return saveAsNew(content, hash: hash, at: date, isSensitive: originalWasSensitive, protectedBoards: [])
        }
        guard canPreview(id) else { return .locked }
        let original = items[index]
        guard ClipboardEditing.text(of: original) != nil else { return .notEditable }
        switch mode {
        case .replace:
            if hash == original.contentHash { return .unchanged }
            if let other = items.first(where: { $0.contentHash == hash && $0.id != id }) { return .duplicate(other.id) }
            var item = items.remove(at: index)
            item.content = content
            item.contentHash = hash
            item.codeDetection = ClipboardCodeDetector.detect(content)
            item.edited = true
            // Other words are another address, or none: what was read of the old page is not theirs.
            item.linkPreview = nil
            item.copiedAt = date
            // Used now, so an ordinary item with a date of now, as `touch` makes one.
            item.exemptFromLimits = nil
            items.insert(item, at: 0)
            return .saved(id)
        case .saveAsNew:
            let protectedBoards = boards(containing: id).filter(\.isProtected).map(\.id)
            return saveAsNew(content, hash: hash, at: date, isSensitive: original.isSensitive, protectedBoards: protectedBoards)
        }
    }

    private mutating func saveAsNew(
        _ content: ClipboardContent, hash: String, at date: Date, isSensitive: Bool, protectedBoards: [UUID]
    ) -> ClipboardEditOutcome {
        if let existing = items.first(where: { $0.contentHash == hash }) {
            let pinnedTo = Set(boards(containing: existing.id).map(\.id))
            guard protectedBoards.allSatisfy(pinnedTo.contains) else { return .duplicate(existing.id) }
            touch(id: existing.id, at: date)
            return .saved(existing.id)
        }
        let id = add(content, hash: hash, source: (nil, nil), at: date, isSensitive: isSensitive).id
        for board in protectedBoards { pin(itemID: id, to: board) }
        return .saved(id)
    }
}
