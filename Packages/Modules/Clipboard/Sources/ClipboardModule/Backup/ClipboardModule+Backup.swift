import Foundation

/// Backing up and restoring the history. Both run off the main actor and report progress; the history is only read when a
/// backup starts and only changed, in one step, when a restore has read its whole file.
extension ClipboardModule {
    /// Writes `destination` (replacing a file there only once the new one is complete). Throws `ClipboardBackupError`, or
    /// `CancellationError` when the task is cancelled, which leaves nothing behind.
    func exportBackup(
        _ options: ClipboardBackupOptions, to destination: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardBackupExportSummary {
        guard let store else { throw ClipboardBackupError.moduleStopped }
        let history = state.history
        var imageURLs: [String: URL] = [:]
        for item in history.items {
            if case .image(let image) = item.content { imageURLs[image.fileName] = store.imageURL(fileName: image.fileName) }
        }
        return try await ClipboardBackupWriter.write(
            history: history, options: options, imageURLs: imageURLs, to: destination, now: now(), progress: progress
        )
    }

    /// Merges the file into the history, without duplicates, then applies the limits from Settings to what was added: an item
    /// older than the retention or beyond the history limit is dropped at once, and the summary says how many. Throws
    /// `ClipboardBackupError`, or `CancellationError`; either way the history is as it was (images read before that stay
    /// in the images folder until the next start removes the ones no item uses).
    func restoreBackup(
        from url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardBackupRestoreSummary {
        guard let store else { throw ClipboardBackupError.moduleStopped }
        let known = Set(state.history.items.map(\.contentHash))
        let plan = try await ClipboardBackupReader.plan(
            archiveAt: url, knownHashes: known, imagesDirectory: store.imagesDirectory, now: now(), progress: progress
        )
        // The module may have been stopped, or stopped and started again, while the file was read.
        guard self.store === store else { throw ClipboardBackupError.moduleStopped }

        var result = ClipboardHistory.RestoreResult()
        var removed: [ClipboardItem] = []
        update { history in
            result = history.restore(plan)
            removed = prune(&history)
            return removed
        }
        // `update` deletes the images of what it removes only when the history ends up changed, which it is not when everything
        // added was dropped again, and those images were written already.
        store.deleteImages(for: removed)
        let added = Set(result.addedIDs)
        let pruned = removed.count(where: { added.contains($0.id) })
        return ClipboardBackupRestoreSummary(
            added: result.addedIDs.count - pruned, duplicates: plan.duplicates + result.duplicates, unreadable: plan.unreadable,
            boardsCreated: result.boardsCreated, prunedByLimits: pruned
        )
    }
}
