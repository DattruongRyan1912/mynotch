import Foundation

/// How a locked board is opened.
nonisolated enum ClipboardLockMethod: String, Codable, Sendable, Equatable {
    /// A password the user types. There is no way back from a forgotten one.
    case password
    /// The board key is in this Mac's Keychain behind Touch ID (or the device password). Bound to this Mac: a backup of the
    /// board cannot be opened anywhere else.
    case touchID
}

/// What the notch and the library know of a locked board while it is locked, and while it is open. In memory only: whether a board
/// is locked is told by the file of its vault, so nothing here is written to `boards.json`.
nonisolated struct ClipboardBoardLock: Hashable, Sendable {
    var method: ClipboardLockMethod
    /// How many items the board holds. Shown while it is locked, when the items themselves are not in memory.
    var itemCount: Int
    /// true while the items are in memory.
    var isUnlocked: Bool
}

nonisolated extension ClipboardBoard {
    /// Whether the board has a lock at all, open or not.
    var isProtected: Bool { lock != nil }
    /// Locked and closed: its items are not in memory.
    var isLocked: Bool { lock.map { !$0.isUnlocked } ?? false }
    /// What to show as the number of items: the count kept with a locked board, otherwise the pins.
    var shownItemCount: Int { isLocked ? lock?.itemCount ?? 0 : itemIDs.count }
}
