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
            await self?.shelve(urls, in: store) ?? urls
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

    /// Gives the files a card each, the first of them first as a drop does, and returns the ones it did not take.
    ///
    /// Results never push other cards off: the shelf drops its oldest cards past its limit, and those can be the
    /// only copy of a text or a promised file (which is deleted with its card). So only as many results are shelved
    /// as there are free places; the rest are on disk next to their sources, and the report says where. The
    /// bookmarks are made off the main actor and the shelf is written once for the whole batch. A run that outlived
    /// its shelf (the module stopped, or stopped and started again) adds nothing to the new one.
    private func shelve(_ urls: [URL], in store: ShelfStore?) async -> [URL] {
        guard let store, state.store === store, let keys, let context else { return urls }
        let limit = context.settings.value(keys.maxItems)
        let wanted = Array(urls.prefix(max(0, limit - store.items.count)))
        let cards = await Self.cards(for: wanted)
        // The shelf may have changed while the bookmarks were made; check the room again.
        guard state.store === store else { return urls }
        let room = max(0, limit - store.items.count)
        let shelved = Array(cards.prefix(room))
        if !shelved.isEmpty { store.add(contentsOf: shelved.map(\.kind).reversed(), limit: limit) }
        let taken = Set(shelved.map(\.url))
        return urls.filter { !taken.contains($0) }
    }

    /// The card each file gets; a file whose bookmark cannot be made gets none.
    @concurrent
    private static func cards(for urls: [URL]) async -> [(url: URL, kind: ShelfItem.Kind)] {
        urls.compactMap { url in (try? ShelfItem.Kind.file(at: url)).map { (url, $0) } }
    }
}
