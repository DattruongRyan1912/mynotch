import AppKit

/// Decides whether closing an editor window must ask first, and what the answers mean.
nonisolated enum EditorClosing {
    /// What the user chose in the alert that closing with unsaved changes shows.
    enum Choice: Equatable, Sendable {
        /// Lưu: saves like the editor's own button (which also copies when Settings says so), then closes.
        case save
        /// Bỏ thay đổi: closes and loses the changes.
        case discard
        /// Tiếp tục sửa: leaves the editor as it is.
        case keepEditing
    }

    /// The alert's buttons, first to last: the first is the default button (Return) and the last is the way out (Esc).
    static let alertButtons = ["Lưu", "Bỏ thay đổi", "Tiếp tục sửa"]

    /// The choice an alert's response stands for. Anything but the first two buttons keeps the editor open, so a sheet
    /// dismissed some other way can never lose the work.
    static func choice(for response: NSApplication.ModalResponse) -> Choice {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertSecondButtonReturn: .discard
        default: .keepEditing
        }
    }

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
