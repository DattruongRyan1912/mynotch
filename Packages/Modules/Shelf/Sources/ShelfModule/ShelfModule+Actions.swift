import Foundation
import UniformTypeIdentifiers

/// The "Hành động" row: which cards are picked, and starting an action on them.
extension ShelfModule {
    /// The picked cards that are still on the shelf, in the order they were picked.
    var selectedItems: [ShelfItem] {
        guard let store = state.store else { return [] }
        return state.selection.compactMap { id in store.items.first { $0.id == id } }
    }

    func isSelected(_ item: ShelfItem) -> Bool { state.selection.contains(item.id) }

    /// Only files can be picked: the actions are for files.
    func toggleSelection(_ item: ShelfItem) {
        guard case .file = item.kind else { return }
        if let index = state.selection.firstIndex(of: item.id) {
            state.selection.remove(at: index)
        } else {
            state.selection.append(item.id)
        }
    }

    /// Runs `action` on the file cards among `items` and returns at once; the progress and the report are in
    /// `state.actions`. Ignored while another action runs. Each file is looked up again first, since it may have
    /// moved. What the settings say (quality, location) is read now.
    func runAction(_ action: FileAction, on items: [ShelfItem]) {
        guard let store = state.store, let keys, let context, !state.actions.isRunning else { return }
        let sources: [ActionSource] = items.compactMap { item in
            guard case .file(_, let name, _) = item.kind else { return nil }
            let url = store.refreshedURL(of: item)
            return ActionSource(name: url?.lastPathComponent ?? name, url: url)
        }
        guard !sources.isEmpty else { return }
        if let group = ShelfActionGroup.containing(action) { state.preferred[group] = action }
        let processor = FileActionProcessor(
            recognizer: recognizer, cutter: cutter,
            quality: context.settings.value(keys.imageQuality), stripLocation: context.settings.value(keys.stripLocation),
            folders: OutputFolders(promisedDirectory: store.promisedDirectory)
        )
        state.actions.start(action, sources: sources, processor: processor, pasteboard: pasteboard) { [weak self, weak store] urls in
            self?.shelve(urls, in: store)
        }
    }

    /// Accepts files dropped on a group of the row at once and loads them in the background, like any drop.
    func runAction(on group: ShelfActionGroup, dropping providers: [NSItemProvider]) -> Bool {
        guard let context, state.store != nil, !providers.isEmpty, !state.actions.isRunning else { return false }
        context.run { [self] in await runAction(on: group, dropped: providers) }
        return true
    }

    /// The files join the shelf, as they would dropped anywhere else on it, and the group's action runs on them:
    /// the choice used last, else its first (PDFs dropped on "PDF" are split, anything else is merged).
    func runAction(on group: ShelfActionGroup, dropped providers: [NSItemProvider]) async {
        let files = await addItems(providers: providers).filter {
            if case .file = $0.kind { true } else { false }
        }
        guard !files.isEmpty else { return }
        let onlyPDFs = files.allSatisfy {
            if case .file(_, _, let type) = $0.kind { type.conforms(to: .pdf) } else { false }
        }
        runAction(group.action(preferred: state.preferred[group], droppingPDFsOnly: onlyPDFs), on: files)
    }

    func cancelAction() { state.actions.cancel() }

    func dismissActionReport() { state.actions.dismiss() }

    /// Copies the text a recognition read once more, for when the clipboard has been used since. False when there
    /// is no text or the pasteboard refused it.
    @discardableResult
    func copyReportText() -> Bool {
        guard case .finished(let report) = state.actions.phase, let text = report.text else { return false }
        return pasteboard.write(text)
    }

    /// Results go to the front of the shelf, the first of them first, as a drop does. A run that outlived its shelf
    /// (the module stopped, or stopped and started again) adds nothing to the new one.
    private func shelve(_ urls: [URL], in store: ShelfStore?) {
        guard let store, state.store === store, let keys, let context else { return }
        for url in urls.reversed() {
            do {
                store.add(try .file(at: url), limit: context.settings.value(keys.maxItems))
            } catch {
                context.logger.error("A result could not be added to the shelf: \(error.localizedDescription)")
            }
        }
    }
}
