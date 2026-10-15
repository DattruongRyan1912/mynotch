import Foundation

/// What the library asks of the module. A protocol so the library's tests change a plain `ClipboardState` and
/// never touch a pasteboard.
protocol ClipboardLibraryActions: AnyObject {
    /// The click action from Settings: copy, or copy and paste. nil while the module is stopped.
    @discardableResult func activate(_ item: ClipboardItem) -> ClipboardPaster.Outcome?
    @discardableResult func copy(_ item: ClipboardItem, plainText: Bool) -> ClipboardPaster.Outcome?
    /// Copies and pastes the item whatever the click action says: the inspector's "Dán". nil while the module is stopped.
    @discardableResult func paste(_ item: ClipboardItem, plainText: Bool) -> ClipboardPaster.Outcome?
    /// Opens the editor window on the item. False when it cannot be edited: not a text or a link, in a closed board, or the module
    /// is stopped.
    @discardableResult func edit(_ item: ClipboardItem) -> Bool
    /// Deletes explicitly, so pinned items go too.
    func delete(ids: Set<UUID>)
    /// `ids` in the order the library shows them, which the board keeps.
    func pin(ids: [UUID], to boardID: UUID)
    /// nil for an empty name or while stopped.
    func createBoard(named name: String) -> UUID?
}
