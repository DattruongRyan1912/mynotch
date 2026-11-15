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
        guard activeCleaningsInFlight == 0 else { throw ClipboardBackupError.busy }
        backupsInFlight += 1
        defer { backupsInFlight -= 1 }
        // An open board may have changed since its vault file was written, which only matters when that file goes in the backup.
        if options.includeLockedBoards { sealOpenBoards() }
        let history = backupHistory
        var imageURLs: [String: URL] = [:]
        for item in history.items {
            if case .image(let image) = item.content { imageURLs[image.fileName] = store.imageURL(fileName: image.fileName) }
        }
        // A board with a lock is never read here, open or not: it goes in sealed as its vault file, or not at all.
        var exports: [ClipboardLockedBoardExport] = []
        var skipped = 0, skippedTouchID = 0
        for board in state.history.boards where board.isProtected {
            if options.includeLockedBoards, board.lock?.method == .password, let vault, vault.files.exists(for: board.id) {
                exports.append(ClipboardLockedBoardExport(
                    id: board.id, name: board.name, systemImage: board.systemImage, color: board.color,
                    itemCount: vault.envelopes[board.id]?.itemCount ?? board.lock?.itemCount ?? 0, file: vault.files.url(for: board.id)
                ))
            } else {
                skipped += 1
                if board.lock?.method == .touchID { skippedTouchID += 1 }
            }
        }
        var summary = try await ClipboardBackupWriter.write(
            history: history, options: options, imageURLs: imageURLs, lockedBoards: exports, to: destination, now: now(), progress: progress
        )
        summary.skippedLockedBoards += skipped
        summary.skippedTouchIDBoards = skippedTouchID
        return summary
    }

    /// The history as a backup sees it: without the boards that have a lock, open or not, and without their items.
    var backupHistory: ClipboardHistory {
        var history = state.history.persistable
        history.boards.removeAll(where: \.isProtected)
        return history
    }

    /// The first step of a restore: reads the file and works out what it would do under the limits in Settings (what would be
    /// added, what the limits would drop of it, what of the history they would drop to make room), and writes nothing: no
    /// item, no board, no image. `commit` of the offer is the second step, once the user has chosen how. Throws
    /// `ClipboardBackupError` (a file the format does not allow, or one that would take the boards over their limit), or
    /// `CancellationError`.
    func planRestore(from url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ClipboardRestoreOffer {
        guard let store, let limits = pruneLimits else { throw ClipboardBackupError.moduleStopped }
        guard activeCleaningsInFlight == 0 else { throw ClipboardBackupError.busy }
        let history = state.history
        let plan = try await ClipboardBackupReader.plan(
            archiveAt: url, knownHashes: Set(history.items.map(\.contentHash)), now: now(), progress: progress
        )
        // The module may have been stopped, or stopped and started again, while the file was read.
        guard self.store === store else { throw ClipboardBackupError.moduleStopped }
        // A board with a lock is not matched by name (its pins would be in the clear), so it is a board of its own to the count.
        var names = history.boards.filter { !$0.isProtected }.map { $0.name.lowercased() }
        for board in plan.boards where !names.contains(board.name.lowercased()) { names.append(board.name.lowercased()) }
        let lockedHere = history.boards.count(where: \.isProtected)
        let lockedNew = plan.lockedBoards.count { board in !history.boards.contains { $0.id == board.id } }
        guard names.count + lockedHere + lockedNew <= ClipboardBackupFormat.maxBoards else { throw ClipboardBackupError.tooManyBoards }

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
        guard self.store === store, let vault else { throw ClipboardBackupError.moduleStopped }
        guard activeCleaningsInFlight == 0 else { throw ClipboardBackupError.busy }
        backupsInFlight += 1
        defer { backupsInFlight -= 1 }
        let written = try await ClipboardBackupReader.writeImages(of: plan, from: url, to: store.imagesDirectory, progress: progress)
        var vaultFiles: [URL] = []
        func discardWrittenFiles() {
            for file in written.created + vaultFiles { try? FileManager.default.removeItem(at: file) }
        }
        let newLocked = plan.lockedBoards.filter { board in !state.history.boards.contains { $0.id == board.id } }
        var lockedFailed = 0
        var restorableLocked: [ClipboardRestorePlan.LockedBoard] = []
        do {
            try Task.checkCancellation()
            guard self.store === store, self.vault === vault else { throw ClipboardBackupError.moduleStopped }
            let sealed = try await ClipboardBackupReader.writeVaults(
                of: plan, boardIDs: Set(newLocked.map(\.id)), from: url, to: vault.files
            )
            vaultFiles = sealed.created
            lockedFailed = sealed.failed.count
            restorableLocked = newLocked.filter { !sealed.failed.contains($0.id) }
            try Task.checkCancellation()
            guard self.store === store else { throw ClipboardBackupError.moduleStopped }
        } catch {
            discardWrittenFiles()
            throw error
        }

        var plan = plan
        var unreadable = plan.unreadable + lockedFailed
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
        var lockedRestored = 0
        update { history in
            // What the limits take of the history as it is, which is not the restore's doing.
            var baseline = history
            takenAnyway = Set(prune(&baseline).map(\.id))
            result = history.restore(plan, exempt: policy == .keepAll)
            lockedRestored = history.restoreLockedBoards(restorableLocked)
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
            boardsCreated: result.boardsCreated, lockedBoardsRestored: lockedRestored, prunedByLimits: droppedAtOnce,
            evictedExisting: removed.count { !added.contains($0.id) && !takenAnyway.contains($0.id) }
        )
    }
}
