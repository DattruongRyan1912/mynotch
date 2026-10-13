import Foundation

/// The whole clipboard history as a value, so every rule is testable without disk or pasteboard.
/// Methods that drop items return them, because only the caller knows how to delete their image files.
nonisolated struct ClipboardHistory: Codable, Equatable, Sendable {
    /// Newest first.
    var items: [ClipboardItem] = []
    var boards: [ClipboardBoard] = []

    enum AddResult: Equatable, Sendable {
        case inserted(UUID)
        /// An item with the same hash was moved to the top instead of adding a duplicate.
        case moved(UUID)

        var id: UUID {
            switch self {
            case .inserted(let id), .moved(let id): id
            }
        }
    }

    /// A repeated copy keeps its id (so pins survive) but takes the newest content, date and source:
    /// rich text and plain text share a hash, so the latest formatting wins.
    @discardableResult
    mutating func add(_ content: ClipboardContent, hash: String, source: (bundleID: String?, name: String?), at date: Date) -> AddResult {
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var item = items.remove(at: index)
            item.content = content
            item.copiedAt = date
            item.sourceBundleID = source.bundleID
            item.sourceAppName = source.name
            items.insert(item, at: 0)
            return .moved(item.id)
        }
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: hash, copiedAt: date,
            sourceBundleID: source.bundleID, sourceAppName: source.name
        )
        items.insert(item, at: 0)
        return .inserted(item.id)
    }

    /// Called when MyNotch reuses an item, so the most recently used one is first.
    mutating func touch(id: UUID, at date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.copiedAt = date
        items.insert(item, at: 0)
    }

    /// Explicit deletion, so pinned items go too and leave their boards.
    mutating func remove(ids: Set<UUID>) -> [ClipboardItem] {
        for index in boards.indices { boards[index].itemIDs.removeAll(where: ids.contains) }
        return removeItems { ids.contains($0.id) }
    }

    /// Clears items copied after `cutoff` (nil clears all), keeping pinned ones.
    mutating func clear(newerThan cutoff: Date?) -> [ClipboardItem] {
        let pinned = pinnedIDs
        return removeItems { item in !pinned.contains(item.id) && (cutoff.map { item.copiedAt > $0 } ?? true) }
    }

    /// Enforces the limits in order: item count, age, then image bytes, each removing the oldest unpinned items first.
    /// Pinned items are never removed but still count toward `limit` and `imageByteLimit`.
    /// Returns the removed items in removal order.
    mutating func prune(limit: Int, retention: Retention, imageByteLimit: Int, now: Date) -> [ClipboardItem] {
        let pinned = pinnedIDs
        var removed: [ClipboardItem] = []
        /// Walks from the oldest item and removes every unpinned one that `shouldRemove` accepts at that moment.
        func removeOldestUnpinned(where shouldRemove: (ClipboardItem) -> Bool) {
            for index in items.indices.reversed() where !pinned.contains(items[index].id) && shouldRemove(items[index]) {
                removed.append(items.remove(at: index))
            }
        }

        removeOldestUnpinned { _ in items.count > limit }
        if let interval = retention.interval {
            let cutoff = now.addingTimeInterval(-interval)
            removeOldestUnpinned { $0.copiedAt < cutoff }
        }
        var imageBytes = items.reduce(0) { $0 + ($1.imageByteCount ?? 0) }
        removeOldestUnpinned { item in
            guard imageBytes > imageByteLimit, let bytes = item.imageByteCount else { return false }
            imageBytes -= bytes
            return true
        }
        return removed
    }

    @discardableResult
    mutating func createBoard(name: String, systemImage: String = "tray.full") -> UUID {
        let board = ClipboardBoard(id: UUID(), name: name, systemImage: systemImage, itemIDs: [])
        boards.append(board)
        return board.id
    }

    mutating func renameBoard(id: UUID, name: String) {
        guard let index = boardIndex(id) else { return }
        boards[index].name = name
    }

    /// The board's items stay in history, unpinned unless another board holds them.
    mutating func deleteBoard(id: UUID) {
        boards.removeAll { $0.id == id }
    }

    /// Ignores unknown items and boards, and items already in the board.
    mutating func pin(itemID: UUID, to boardID: UUID) {
        guard items.contains(where: { $0.id == itemID }), let index = boardIndex(boardID),
              !boards[index].itemIDs.contains(itemID) else { return }
        boards[index].itemIDs.insert(itemID, at: 0)
    }

    mutating func unpin(itemID: UUID, from boardID: UUID) {
        guard let index = boardIndex(boardID) else { return }
        boards[index].itemIDs.removeAll { $0 == itemID }
    }

    func isPinned(_ id: UUID) -> Bool {
        boards.contains { $0.itemIDs.contains(id) }
    }

    func boards(containing itemID: UUID) -> [ClipboardBoard] {
        boards.filter { $0.itemIDs.contains(itemID) }
    }

    private var pinnedIDs: Set<UUID> {
        Set(boards.flatMap(\.itemIDs))
    }

    private func boardIndex(_ id: UUID) -> Int? {
        boards.firstIndex { $0.id == id }
    }

    /// Removes matching items and returns them in history order.
    private mutating func removeItems(where matches: (ClipboardItem) -> Bool) -> [ClipboardItem] {
        let removed = items.filter(matches)
        items.removeAll(where: matches)
        return removed
    }
}

private nonisolated extension ClipboardItem {
    var imageByteCount: Int? {
        if case .image(let image) = content { image.byteCount } else { nil }
    }
}
