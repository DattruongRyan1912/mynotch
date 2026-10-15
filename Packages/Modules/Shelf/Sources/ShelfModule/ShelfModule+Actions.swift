import AppKit
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
        let promised = OutputFolders(promisedDirectory: store.promisedDirectory), results = resultsFolder
        state.actions.start(action, sources: sources, processor: processor, pasteboard: pasteboard) { [weak self, weak store] urls in
            guard let self else {
                return await Self.makeReachable(urls.map { UnshelvedResult(url: $0, reason: .shelfStopped) }, folders: promised, into: results)
            }
            return await deliverResults(urls, to: store, promised: promised)
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

    /// Shows the files in Finder, for the results that have no card.
    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// What happens to the results of one source: they get cards as far as there is room, and the ones left without
    /// are taken out of the shelf's promised storage if that is where they are, so no result is left where the next
    /// launch deletes it. Returns the results without a card, with why.
    func deliverResults(_ urls: [URL], to store: ShelfStore?, promised: OutputFolders) async -> [UnshelvedResult] {
        let left = await shelve(urls, in: store)
        return await Self.makeReachable(left, folders: promised, into: resultsFolder)
    }

    /// Gives the files a card each, the first of them first as a drop does, and returns the ones it left without,
    /// with why.
    ///
    /// Results never evict: the shelf drops its oldest cards past its limit, and those can be the only copy of a text
    /// or a promised file (which is deleted with its card). So only as many results are shelved as there are free
    /// places; the rest stay on disk and the report says where. The bookmarks are made off the main actor and the
    /// shelf is written once for the whole batch. A run that outlived its shelf (the module stopped, or stopped and
    /// started again) adds nothing to the new one.
    private func shelve(_ urls: [URL], in store: ShelfStore?) async -> [UnshelvedResult] {
        func all(_ reason: UnshelvedResult.Reason) -> [UnshelvedResult] { urls.map { UnshelvedResult(url: $0, reason: reason) } }
        guard let store, state.store === store, let keys, let context else { return all(.shelfStopped) }
        let limit = context.settings.value(keys.maxItems)
        let wanted = Array(urls.prefix(max(0, limit - store.items.count)))
        let cards = await Self.cards(for: wanted, make: makeCard)
        // The shelf may have changed while the bookmarks were made; check the room again.
        guard state.store === store else { return all(.shelfStopped) }
        let room = max(0, limit - store.items.count)
        var shelved: [ShelfItem.Kind] = []
        var left: [UnshelvedResult] = []
        for (index, url) in urls.enumerated() {
            if index < cards.count, cards[index].kind == nil {
                left.append(UnshelvedResult(url: url, reason: .cardFailed))
            } else if index < cards.count, shelved.count < room, let kind = cards[index].kind {
                shelved.append(kind)
            } else {
                left.append(UnshelvedResult(url: url, reason: .shelfFull))
            }
        }
        if !shelved.isEmpty { store.add(contentsOf: shelved.reversed(), limit: limit) }
        return left
    }

    /// The card each file gets; nil for a file whose bookmark cannot be made.
    @concurrent
    private static func cards(for urls: [URL], make: @Sendable (URL) throws -> ShelfItem.Kind) async -> [(url: URL, kind: ShelfItem.Kind?)] {
        urls.map { url in (url, try? make(url)) }
    }

    /// Takes the results without a card out of the shelf's promised storage, which the next launch sweeps.
    @concurrent
    private static func makeReachable(_ results: [UnshelvedResult], folders: OutputFolders, into folder: URL) async -> [UnshelvedResult] {
        ResultsFolder.rescue(results, folders: folders, into: folder)
    }
}
