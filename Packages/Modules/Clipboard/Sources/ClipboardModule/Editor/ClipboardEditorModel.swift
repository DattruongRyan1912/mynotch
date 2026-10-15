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
        didSet {
            guard text != oldValue else { return }
            notice = nil
            // Working in the editor of a secret is using the board it is in, which must not lock under it for being idle.
            if isProtected { onActivity?() }
        }
    }
    /// The item is pinned to a board that has a lock (open, or it could not be edited): its words are a secret that must not outlive the
    /// lock. Set when the editor opens and kept up to date by the module as the history changes, since the history no longer says so
    /// at the change that takes the item away.
    var isProtected: Bool
    /// Whether the item was a secret when last seen, for the words to carry the flag if they are saved after it is gone.
    var wasSensitive: Bool
    /// Told when the user types and the item is protected.
    @ObservationIgnored var onActivity: (() -> Void)?
    var isMonospaced: Bool
    /// The language the words look like they are in now, for the footer; found in the background as the user types.
    var detectedLanguage: CodeLanguage?
    /// A rich text item: what is saved is its plain words.
    let losesFormatting: Bool
    private(set) var isConfirmingDiscard = false
    /// Why the last save did nothing, until the words change again.
    private(set) var notice: String?
    /// The item left the history (pruned, deleted, cleared) while it was edited and it was not a secret: the words here are all that is
    /// left of it. They stay, and only a new item can hold them.
    private(set) var isOriginalGone = false
    /// The item was a secret of a board that locked while it had unsaved words: they are wiped, and the editor stays, empty and read-only,
    /// with a lasting caption saying so, until the user closes it.
    private(set) var isDroppedOnLock = false

    @ObservationIgnored private let saveAction: Save
    @ObservationIgnored private let closeAction: () -> Void
    @ObservationIgnored private var isClosed = false

    init(item: ClipboardItem, text: String, isProtected: Bool = false, save: @escaping Save, close: @escaping () -> Void) {
        itemID = item.id
        self.isProtected = isProtected
        wasSensitive = item.isSensitive
        originalText = text
        self.text = text
        isMonospaced = item.isCode
        detectedLanguage = item.codeLanguage
        if case .richText = item.content { losesFormatting = true } else { losesFormatting = false }
        saveAction = save
        closeAction = close
    }

    /// The words differ from the item's.
    var hasEditedWords: Bool { text != originalText }
    /// There is something to lose by closing: edited words, or words that are the only copy left of an item that is gone.
    var hasChanges: Bool { hasEditedWords || isOriginalGone }
    /// Both save buttons: something changed, and the result is not blank.
    var canSave: Bool { hasChanges && !text.allSatisfy(\.isWhitespace) }
    /// "Thay thế mục này" needs the item to be there.
    var canReplace: Bool { canSave && !isOriginalGone }

    /// "Lưu thành mục mới" and "Thay thế mục này". Closes when the history took the words; otherwise stays and says why.
    func save(_ mode: ClipboardEditMode) {
        guard canSave else { return }
        guard mode == .saveAsNew || !isOriginalGone else {
            notice = Self.words(for: .missing)
            return
        }
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

    /// The item left the history and it was not a secret: the editor stays open with its words, and says so.
    func originalGone() {
        isOriginalGone = true
    }

    /// The item of a locked board is no longer in the history: there is nothing to save to or ask about, and the words must not
    /// outlive the lock, so the editor lets go of them at once. With nothing unsaved it closes. With edited words it stays, empty, to
    /// say what happened where the user is looking (`isDroppedOnLock`), and closes when they do. Wiping is not typing: it must not
    /// count as activity, which would keep another open board from locking when it should.
    func itemGone() {
        guard !isDroppedOnLock else { return }
        onActivity = nil
        isConfirmingDiscard = false
        let hadWords = hasEditedWords
        originalText = ""
        text = ""
        if hadWords { isDroppedOnLock = true } else { closeNow() }
    }

    private func closeNow() {
        guard !isClosed else { return }
        isClosed = true
        closeAction()
    }

    /// Over the editor while its original is gone.
    static let originalGoneNotice = "Mục gốc không còn trong lịch sử. Nội dung này vẫn lưu được thành mục mới."
    /// What a toast says when a lock closes an editor that had unsaved words: that, and nothing of the words or of the item.
    static let droppedOnLockNotice = "Board đã khoá nên bản sửa chưa lưu đã bị bỏ"
    /// The lasting caption of an editor whose words a lock dropped: the same, and what can be done.
    static let droppedOnLockCaption = droppedOnLockNotice + ". Mở khoá board rồi sửa lại nếu cần."

    static func words(for outcome: ClipboardEditOutcome) -> String? {
        switch outcome {
        case .saved: nil
        case .unchanged: "Nội dung chưa thay đổi."
        case .blank: "Nội dung đang trống."
        case .tooLarge: "Nội dung quá dài: tối đa 2 MB."
        case .duplicate:
            "Đã có một mục khác với đúng nội dung này, nên chưa lưu được. Hãy sửa nội dung cho khác đi, hoặc chép nội dung này (⌘A, ⌘C) để dùng ở nơi khác."
        case .missing: "Mục gốc không còn trong lịch sử, nên không thay thế được."
        case .locked: "Không lưu được: mục này đang nằm trong board đã khoá."
        case .notEditable: "Loại mục này không sửa được."
        case .stopped: "Clipboard đang tắt nên chưa lưu được."
        }
    }
}
