import Foundation
import Observation

/// One editor window's decisions apart from its drawing: the words being edited, whether they changed, how they are saved and what
/// leaving does with unsaved ones. The module gives it the way to save and the way to close, so it never touches the history or a
/// window itself.
@Observable
final class ClipboardEditorModel {
    /// Saves `text` the way `mode` says and answers what happened; the module's `saveEdit`.
    typealias Save = (ClipboardEditMode, String) -> ClipboardEditOutcome

    let itemID: UUID
    /// What the item said when the editor opened; "changed" means different from this.
    private(set) var originalText: String
    var text: String {
        didSet { if text != oldValue { notice = nil } }
    }
    var isMonospaced: Bool
    /// The language the words look like they are in now, for the footer; found in the background as the user types.
    var detectedLanguage: CodeLanguage?
    /// A rich text item: what is saved is its plain words.
    let losesFormatting: Bool
    private(set) var isConfirmingDiscard = false
    /// Why the last save did nothing, until the words change again.
    private(set) var notice: String?

    @ObservationIgnored private let saveAction: Save
    @ObservationIgnored private let closeAction: () -> Void
    @ObservationIgnored private var isClosed = false

    init(item: ClipboardItem, text: String, save: @escaping Save, close: @escaping () -> Void) {
        itemID = item.id
        originalText = text
        self.text = text
        isMonospaced = item.isCode
        detectedLanguage = item.codeLanguage
        if case .richText = item.content { losesFormatting = true } else { losesFormatting = false }
        saveAction = save
        closeAction = close
    }

    var hasChanges: Bool { text != originalText }
    /// Both save buttons: something changed, and the result is not blank.
    var canSave: Bool { hasChanges && !text.allSatisfy(\.isWhitespace) }

    /// "Lưu thành mục mới" and "Thay thế mục này". Closes when the history took the words; otherwise stays and says why.
    func save(_ mode: ClipboardEditMode) {
        guard canSave else { return }
        let outcome = saveAction(mode, text)
        if case .saved = outcome {
            closeNow()
        } else {
            notice = Self.words(for: outcome)
        }
    }

    /// Esc, ⌘W and "Huỷ": leaves at once, or asks first when there are unsaved words.
    func cancel() {
        if hasChanges { isConfirmingDiscard = true } else { closeNow() }
    }

    /// The window's own close button: whether it may close now. When not, the question is asked instead.
    func windowShouldClose() -> Bool {
        guard hasChanges else { return true }
        isConfirmingDiscard = true
        return false
    }

    func keepEditing() {
        isConfirmingDiscard = false
    }

    func discard() {
        isConfirmingDiscard = false
        closeNow()
    }

    /// The item is no longer in the history (deleted, or its board locked): there is nothing to save to or ask about, and the words
    /// must not outlive a board that was locked, so the editor closes at once and lets go of them.
    func itemGone() {
        isConfirmingDiscard = false
        originalText = ""
        text = ""
        closeNow()
    }

    private func closeNow() {
        guard !isClosed else { return }
        isClosed = true
        closeAction()
    }

    static func words(for outcome: ClipboardEditOutcome) -> String? {
        switch outcome {
        case .saved: nil
        case .unchanged: "Nội dung chưa thay đổi."
        case .blank: "Nội dung đang trống."
        case .tooLarge: "Nội dung quá dài: tối đa 2 MB."
        case .duplicate: "Đã có một mục khác với đúng nội dung này. Chọn “Lưu thành mục mới” để đưa mục đó lên đầu."
        case .missing: "Mục gốc không còn trong lịch sử."
        case .locked: "Không lưu được: mục này đang nằm trong board đã khoá."
        case .notEditable: "Loại mục này không sửa được."
        case .stopped: "Clipboard đang tắt nên chưa lưu được."
        }
    }
}
