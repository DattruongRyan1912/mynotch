import SwiftUI

/// The editor windows the module has open, keyed by the item being edited. A holder of its own so the module's class needs one line
/// for it; tests replace `windowing` with a fake before opening anything.
final class ClipboardEditors {
    /// Made the first time an editor opens, so a module that never opens one never makes it.
    lazy var windowing: any ClipboardEditorWindowing = ClipboardEditorWindowController()
    fileprivate(set) var open: [UUID: ClipboardEditorModel] = [:]
}

/// Editing the words of a text or a link in the library: opening the editor, and saving what it made into the history. Saving never
/// writes the pasteboard.
extension ClipboardModule {
    /// Opens the editor on `item`, or brings its window forward when it is open already. False when the item cannot be edited (not a
    /// text or a link, in a closed board, gone) or the module is stopped.
    @discardableResult
    func edit(_ item: ClipboardItem) -> Bool {
        guard store != nil, state.history.canEdit(item.id), let text = ClipboardEditing.text(of: item) else { return false }
        if editors.open[item.id] != nil {
            editors.windowing.bringToFront(itemID: item.id)
            return true
        }
        let id = item.id
        let model = ClipboardEditorModel(
            item: item, text: text,
            save: { [weak self] mode, text in self?.saveEdit(of: id, text: text, mode: mode) ?? .stopped },
            close: { [weak self] in self?.editors.windowing.close(itemID: id) }
        )
        editors.open[id] = model
        // An item that leaves the history (deleted, or its board locked, or the module stopping) takes its editor with it.
        state.observeHistory(model) { [weak self, weak model] in
            guard let self, let model, !self.state.history.items.contains(where: { $0.id == id }) else { return }
            model.itemGone()
        }
        editors.windowing.show(AnyView(ClipboardEditorView(model: model)), model: model) { [weak self] in
            self?.editorClosed(id)
        }
        return true
    }

    /// Puts the words into the history: as a new item on top, or in place of the item. What happened, or why nothing did.
    func saveEdit(of id: UUID, text: String, mode: ClipboardEditMode) -> ClipboardEditOutcome {
        guard let context, let keys, store != nil else { return .stopped }
        let content: ClipboardContent
        switch ClipboardEditing.classify(text, colorsWithoutHash: context.settings.value(keys.colorsWithoutHash)) {
        case .refused(let outcome): return outcome
        case .content(let classified): content = classified
        }
        var outcome = ClipboardEditOutcome.missing
        update { history in
            outcome = history.applyEdit(to: id, content: content, mode: mode, at: now())
            return []
        }
        return outcome
    }

    /// The editor of `id` was closed, by the user or by the module.
    private func editorClosed(_ id: UUID) {
        guard let model = editors.open.removeValue(forKey: id) else { return }
        state.stopObservingHistory(model)
    }
}
