/// Decides whether closing an editor window must ask first.
nonisolated enum EditorClosing {
    /// True when the editor holds changes that were not saved and nothing (a save, closing everything) already
    /// settled the question.
    static func needsConfirmation(current: MarkupDocument, saved: MarkupDocument, closesWithoutAsking: Bool) -> Bool {
        !closesWithoutAsking && current != saved
    }
}
