import Foundation

/// The rules of a locked board on the history as a value. A board with a lock keeps its items in the history only while it is
/// open, and what is written to disk never holds them: they are in the vault file, sealed.
nonisolated extension ClipboardHistory {
    /// The items pinned to a board that has a lock, open or not: the ones that must not be written in the clear, nor handed to agents.
    var protectedItemIDs: Set<UUID> {
        Set(boards.filter(\.isProtected).flatMap(\.itemIDs))
    }

    /// The items in memory that are pinned to the board, in the order of its pins (newest first).
    func items(of boardID: UUID) -> [ClipboardItem] {
        guard let board = boards.first(where: { $0.id == boardID }) else { return [] }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return board.itemIDs.compactMap { byID[$0] }
    }

    /// What goes into `history.json` and `boards.json`: without the items of boards that have a lock, and without any pin to them
    /// (a board of the file that is locked has no pins, an ordinary board does not point at an item that is not written).
    var persistable: ClipboardHistory {
        let hidden = protectedItemIDs
        guard !hidden.isEmpty else { return self }
        var copy = self
        copy.items.removeAll { hidden.contains($0.id) }
        for index in copy.boards.indices { copy.boards[index].itemIDs.removeAll(where: hidden.contains) }
        return copy
    }

    /// Closes the board: its items leave the history, and every board's pins to them with it (an item pinned to two boards would
    /// otherwise stay in the clear in the other), and the board is shown as locked with the number it held. Returns the items in the
    /// order of the pins, which the caller seals, and whose images it deletes. Does nothing for an unknown board.
    mutating func lockBoard(id: UUID, method: ClipboardLockMethod) -> [ClipboardItem] {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return [] }
        let sealed = items(of: id)
        let ids = Set(sealed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        for position in boards.indices { boards[position].itemIDs.removeAll(where: ids.contains) }
        boards[index].lock = ClipboardBoardLock(method: method, itemCount: sealed.count, isUnlocked: false)
        return sealed
    }

    /// Opens a locked board with the items its vault held (in the order of its pins): they are put back where their dates place them
    /// and pinned in that order. An item whose words the history has by now (copied again while the board was closed) is not
    /// added twice: the history's own is the one pinned. Returns the ids pinned; does nothing for a board that is not locked.
    @discardableResult
    mutating func unlockBoard(id: UUID, with sealed: [ClipboardItem]) -> [UUID] {
        guard let index = boards.firstIndex(where: { $0.id == id }), let lock = boards[index].lock, !lock.isUnlocked else { return [] }
        var idByHash = Dictionary(items.map { ($0.contentHash, $0.id) }, uniquingKeysWith: { first, _ in first })
        var fresh: [ClipboardItem] = []
        var pinned: [UUID] = []
        for item in sealed {
            let itemID = idByHash[item.contentHash] ?? item.id
            if idByHash[item.contentHash] == nil {
                idByHash[item.contentHash] = item.id
                fresh.append(item)
            }
            if !pinned.contains(itemID) { pinned.append(itemID) }
        }
        mergeNewestFirst(fresh)
        boards[index].itemIDs = pinned
        boards[index].lock = ClipboardBoardLock(method: lock.method, itemCount: pinned.count, isUnlocked: true)
        return pinned
    }

    /// The board becomes an ordinary one again, its items staying pinned and now written like any other.
    mutating func removeLock(id: UUID) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].lock = nil
    }

    /// Deletes a board that has a lock together with the items in memory that are pinned to it: they were meant to be kept private,
    /// so they do not become ordinary history. Returns the removed items, whose images are deleted by the caller.
    mutating func deleteProtectedBoard(id: UUID) -> [ClipboardItem] {
        let removed = items(of: id)
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        for index in boards.indices { boards[index].itemIDs.removeAll(where: ids.contains) }
        boards.removeAll { $0.id == id }
        return removed
    }
}
