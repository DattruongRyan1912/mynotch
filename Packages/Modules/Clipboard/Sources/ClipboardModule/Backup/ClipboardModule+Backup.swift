import Foundation

/// Backing up and restoring the history. Reading and writing run off the main actor and report progress; the history is only
/// read when a backup starts and only changed, in one step, when a restore has been chosen and its images stored.
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

    /// The first step of a restore: reads the file and works out what it would do under the limits in Settings (what would be
    /// added, what the limits would drop of it, what of the history they would drop to make room), and writes nothing: no
    /// item, no board, no image. `commit` of the offer is the second step, once the user has chosen how. Throws
    /// `ClipboardBackupError` (a file the format does not allow, or one that would take the boards over their limit), or
    /// `CancellationError`.
    func planRestore(from url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ClipboardRestoreOffer {
        guard let store, let limits = pruneLimits else { throw ClipboardBackupError.moduleStopped }
        let history = state.history
        let plan = try await ClipboardBackupReader.plan(
            archiveAt: url, knownHashes: Set(history.items.map(\.contentHash)), now: now(), progress: progress
        )
        // The module may have been stopped, or stopped and started again, while the file was read.
        guard self.store === store else { throw ClipboardBackupError.moduleStopped }
        var names = history.boards.map { $0.name.lowercased() }
        for board in plan.boards where !names.contains(board.name.lowercased()) { names.append(board.name.lowercased()) }
        guard names.count <= ClipboardBackupFormat.maxBoards else { throw ClipboardBackupError.tooManyBoards }

        let summary = await ClipboardRestoreImpact.summary(of: plan, on: history, limits: limits, now: now())
        return ClipboardRestoreOffer(summary: summary) { [weak self] policy, progress in
            guard let self else { throw ClipboardBackupError.moduleStopped }
            return try await self.commitRestore(plan, from: url, in: store, policy: policy, progress: progress)
        }
    }

    /// The second step: stores the images of what is to be added, then merges, in one change, with the limits applied or not as
    /// `policy` says. When it ends in an error or is cancelled the history is as it was and no image it stored is left.
    private func commitRestore(
        _ plan: ClipboardRestorePlan, from url: URL, in store: ClipboardStore, policy: ClipboardRestorePolicy,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ClipboardBackupRestoreSummary {
        guard self.store === store else { throw ClipboardBackupError.moduleStopped }
        let written = try await ClipboardBackupReader.writeImages(of: plan, from: url, to: store.imagesDirectory, progress: progress)
        func discardImages() {
            for file in written.created { try? FileManager.default.removeItem(at: file) }
        }
        do {
            try Task.checkCancellation()
            guard self.store === store else { throw ClipboardBackupError.moduleStopped }
        } catch {
            discardImages()
            throw error
        }

        var plan = plan
        var unreadable = plan.unreadable
        if !written.failed.isEmpty {
            // The file is no longer what was read: an item whose image is not there any more cannot be restored.
            let before = plan.items.count
            plan.items.removeAll { item in
                if case .image(let image) = item.content { written.failed.contains(image.fileName) } else { false }
            }
            unreadable += before - plan.items.count
        }
        plan.boards = plan.boards.map { board in
            var board = board
            if !ClipboardBoardIcon.exists(board.systemImage) { board.systemImage = ClipboardBoardIcon.defaultName }
            return board
        }

        var result = ClipboardHistory.RestoreResult()
        var removed: [ClipboardItem] = []
        var takenAnyway = Set<UUID>()
        update { history in
            // What the limits take of the history as it is, which is not the restore's doing.
            var baseline = history
            takenAnyway = Set(prune(&baseline).map(\.id))
            result = history.restore(plan, exempt: policy == .keepAll)
            removed = prune(&history)
            return removed
        }
        // `update` deletes the images of what it removes only when the history ends up changed, which it is not when everything
        // added was dropped again, and those images were stored already.
        store.deleteImages(for: removed)
        let added = Set(result.addedIDs)
        let droppedAtOnce = removed.count { added.contains($0.id) }
        return ClipboardBackupRestoreSummary(
            added: result.addedIDs.count - droppedAtOnce, duplicates: plan.duplicates + result.duplicates, unreadable: unreadable,
            boardsCreated: result.boardsCreated, prunedByLimits: droppedAtOnce,
            evictedExisting: removed.count { !added.contains($0.id) && !takenAnyway.contains($0.id) }
        )
    }
}
