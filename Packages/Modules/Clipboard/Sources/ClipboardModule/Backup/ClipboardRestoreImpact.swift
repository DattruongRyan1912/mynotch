import Foundation

/// How a restore is applied to the history.
nonisolated enum ClipboardRestorePolicy: Sendable, Equatable {
    /// What is restored is kept whatever the limits say, and nothing that was there is removed to make room.
    case keepAll
    /// The limits in Settings apply to what is restored as to any copy: what falls outside is dropped at once, and older
    /// items that were there make room when the history is at its limit.
    case applyLimits
}

/// What a restore would do, worked out before it does anything, for the user to choose by.
nonisolated struct ClipboardRestorePlanSummary: Sendable, Equatable {
    /// Items of the file that are new to the history.
    var added = 0
    var duplicates = 0
    /// Items of the file that could not be read.
    var unreadable = 0
    var boardsToCreate = 0
    /// Locked boards of the file that are not here yet; each comes back sealed, to be opened with its own password.
    var lockedBoards = 0
    /// New items the limits in Settings would drop at once (older than the retention, or beyond the history limit).
    var outsideLimits = 0
    /// Items that are in the history now, unpinned, that the limits would drop to make room for the new ones, and how many of
    /// them are images, whose files go too. Items the limits would drop anyway are not counted.
    var evictedExisting = 0
    var evictedExistingImages = 0

    /// Whether the two ways to restore differ: when nothing falls outside the limits and nothing is evicted, they do not.
    var affectsHistory: Bool { outsideLimits > 0 || evictedExisting > 0 }
}

/// A restore that has been read and not yet done: what it would do, and the way to do it once the user has chosen. Nothing has
/// been written when this exists.
struct ClipboardRestoreOffer {
    let summary: ClipboardRestorePlanSummary
    let commit: (ClipboardRestorePolicy, @escaping @Sendable (Double) -> Void) async throws -> ClipboardBackupRestoreSummary
}

/// Works out the outcome of a restore on a copy of the history.
nonisolated enum ClipboardRestoreImpact {
    struct Limits: Sendable, Equatable {
        var limit: Int
        var retention: Retention
        var imageByteLimit: Int
    }

    /// Merges the plan into a copy of `history` and applies the limits to it, as a restore under `.applyLimits` would, and counts
    /// what that takes away. Off the main actor, since it walks the whole history.
    @concurrent static func summary(
        of plan: ClipboardRestorePlan, on history: ClipboardHistory, limits: Limits, now: Date
    ) async -> ClipboardRestorePlanSummary {
        func prune(_ history: inout ClipboardHistory) -> [ClipboardItem] {
            history.prune(limit: limits.limit, retention: limits.retention, imageByteLimit: limits.imageByteLimit, now: now)
        }
        // What the limits take now, with nothing restored: the next change to the history takes it whatever happens here.
        var baseline = history
        let takenAnyway = Set(prune(&baseline).map(\.id))

        var merged = history
        let result = merged.restore(plan)
        let added = Set(result.addedIDs)
        let removed = prune(&merged)
        let evicted = removed.filter { !added.contains($0.id) && !takenAnyway.contains($0.id) }
        return ClipboardRestorePlanSummary(
            added: result.addedIDs.count, duplicates: plan.duplicates + result.duplicates, unreadable: plan.unreadable,
            boardsToCreate: result.boardsCreated, lockedBoards: plan.lockedBoards.count { board in !history.boards.contains { $0.id == board.id } },
            outsideLimits: removed.count { added.contains($0.id) },
            evictedExisting: evicted.count, evictedExistingImages: evicted.count { if case .image = $0.content { true } else { false } }
        )
    }
}
