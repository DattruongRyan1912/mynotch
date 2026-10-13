/// Decides whether closing an editor window must ask first.
nonisolated enum EditorClosing {
    /// True when the editor holds changes that were not saved and nothing (a save, closing everything) already
    /// settled the question.
    static func needsConfirmation(current: MarkupDocument, saved: MarkupDocument, closesWithoutAsking: Bool) -> Bool {
        !closesWithoutAsking && current != saved
    }

    /// Whether the window closes once a save is done: not when the editor changed while it ran, since `saved` is
    /// what the file holds and the newer edits would be lost.
    static func shouldCloseAfterSave(saved: MarkupDocument, current: MarkupDocument) -> Bool {
        saved == current
    }
}
