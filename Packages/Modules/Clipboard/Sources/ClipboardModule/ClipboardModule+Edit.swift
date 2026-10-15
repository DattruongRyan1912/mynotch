import SwiftUI

/// The editor windows the module has open, keyed by the item being edited. A holder of its own so the module's class needs one line
/// for it; tests replace `windowing` with a fake before opening anything.
final class ClipboardEditors {
    /// How long typing in the editor of a secret counts as one note of activity for the open board's idle time.
    static let activityInterval: TimeInterval = 10

    /// Made the first time an editor opens, so a module that never opens one never makes it.
    lazy var windowing: any ClipboardEditorWindowing = ClipboardEditorWindowController()
    fileprivate(set) var open: [UUID: ClipboardEditorModel] = [:]
    /// When typing last restarted the idle time of an open board.
    fileprivate var lastActivity: Date?
}

/// Editing the words of a text or a link in the library: opening the editor, and saving what it made into the history. Saving never
/// writes the pasteboard.
extension ClipboardModule {
    /// Opens the editor on `item`, or brings its window forward when it is open already. False when the item cannot be edited (not a
    /// text or a link, in a closed board, gone) or the module is stopped. The words are the ones in the history now, not those of a
    /// card that may be older.
    @discardableResult
    func edit(_ item: ClipboardItem) -> Bool {
        guard store != nil, let current = state.history.items.first(where: { $0.id == item.id }),
              state.history.canEdit(current.id), let text = ClipboardEditing.text(of: current) else { return false }
        if editors.open[current.id] != nil {
            editors.windowing.bringToFront(itemID: current.id)
            return true
        }
        let id = current.id
        let model = ClipboardEditorModel(
            item: current, text: text, isProtected: state.history.protectedItemIDs.contains(id),
            save: { [weak self] mode, text in self?.saveEdit(of: id, text: text, mode: mode) ?? .stopped },
            close: { [weak self] in self?.editors.windowing.close(itemID: id) }
        )
        model.onActivity = { [weak self] in self?.editorWasTypedIn() }
        editors.open[id] = model
        state.observeHistory(model) { [weak self, weak model] in
            guard let self, let model else { return }
            self.historyChangedUnderEditor(model)
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
        // An original that is gone and was no secret: its words can still be saved as a new item.
        let editor = editors.open[id]
        let originalWasSensitive = editor.flatMap { $0.isOriginalGone && !$0.isProtected ? $0.wasSensitive : nil }
        var outcome = ClipboardEditOutcome.missing
        update { history in
            outcome = history.applyEdit(to: id, content: content, mode: mode, at: now(), originalWasSensitive: originalWasSensitive)
            return []
        }
        // The copy stack holds snapshots of items: it must not paste, or write to its file, the words that were just replaced.
        if mode == .replace, case .saved = outcome, let updated = state.history.items.first(where: { $0.id == id }) {
            updateStack { $0.refresh(with: updated) }
        }
        return outcome
    }

    /// Stopping the module (quitting, Pause All, turning Clipboard off) leaves no way to ask what to do with unsaved words, so the
    /// words of an editor of an ordinary item that were edited are saved as a new item before the history is written, and the editors
    /// close. Editors of secrets have been wiped by then (`stopVault` closes every open board first), and an editor that was not edited
    /// adds nothing, so an item that was deleted while its editor was open does not come back.
    func saveEditorDraftsBeforeStopping() {
        for model in Array(editors.open.values) {
            if !model.isProtected, model.hasEditedWords, model.canSave {
                _ = saveEdit(of: model.itemID, text: model.text, mode: .saveAsNew)
            }
            editors.windowing.close(itemID: model.itemID)
        }
    }

    /// The history changed while `model`'s editor is open. An item still there is looked at again (it may have been pinned to, or taken
    /// out of, a board that has a lock). An item that is gone takes its editor with it, and the words, only if it was a secret: a
    /// board that locked, or was deleted. Otherwise (pruned, deleted, cleared) the editor stays with the words and says the original is
    /// gone.
    private func historyChangedUnderEditor(_ model: ClipboardEditorModel) {
        let history = state.history
        if let item = history.items.first(where: { $0.id == model.itemID }) {
            model.isProtected = history.protectedItemIDs.contains(item.id)
            model.wasSensitive = item.isSensitive
        } else if model.isProtected {
            // An editor that already shows the notice has said it: later changes of the history leave it be until it is closed.
            guard !model.isDroppedOnLock else { return }
            model.itemGone()
            // The editor shows the notice itself, for the user who is looking at it; the toast is for one who is not. Without a word of
            // what it was in either: only that an edit was dropped.
            if model.isDroppedOnLock { showToast(ClipboardEditorModel.droppedOnLockNotice, systemImage: "lock.fill") }
        } else {
            model.originalGone()
        }
    }

    /// Typing in the editor of a secret: the open board's idle time starts again, at most once in a while.
    private func editorWasTypedIn() {
        let moment = now()
        if let last = editors.lastActivity, moment.timeIntervalSince(last) < ClipboardEditors.activityInterval { return }
        editors.lastActivity = moment
        noteVaultActivity()
    }

    /// The editor of `id` was closed, by the user or by the module.
    private func editorClosed(_ id: UUID) {
        guard let model = editors.open.removeValue(forKey: id) else { return }
        state.stopObservingHistory(model)
    }
}
