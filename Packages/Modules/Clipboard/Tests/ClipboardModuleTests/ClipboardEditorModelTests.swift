import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// The editor as its model decides it: what counts as a change, how it saves, and what Esc, ⌘W and the close button do with
/// unsaved words.
@Suite final class ClipboardEditorModelTests {
    typealias Keys = ClipboardPreviewKeys

    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// What the editor asked for, and what the history answers next.
    var saves: [(mode: ClipboardEditMode, text: String)] = []
    var closed = 0
    var answer: ClipboardEditOutcome = .saved(UUID())

    func make(_ content: ClipboardContent = .text("Xin chào")) -> ClipboardEditorModel {
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: Self.start,
            codeDetection: ClipboardCodeDetector.detect(content)
        )
        return ClipboardEditorModel(
            item: item, text: ClipboardEditing.text(of: item) ?? "",
            save: { [unowned self] mode, text in
                saves.append((mode, text))
                return answer
            },
            close: { [unowned self] in closed += 1 }
        )
    }

    // MARK: What counts as a change

    @Test func itStartsWithTheItemsWordsAndNothingToSave() {
        let model = make()
        #expect(model.text == "Xin chào" && model.originalText == "Xin chào")
        #expect(!model.hasChanges && !model.canSave)
    }

    @Test func editingIsAChangeAndPuttingItBackIsNot() {
        let model = make()
        model.text = "Xin chào bạn"
        #expect(model.hasChanges && model.canSave)
        model.text = "Xin chào"
        #expect(!model.hasChanges && !model.canSave)
    }

    @Test func blankWordsAreAChangeThatCannotBeSaved() {
        let model = make()
        model.text = "  \n "
        #expect(model.hasChanges)
        #expect(!model.canSave)
        model.text = ""
        #expect(!model.canSave)
    }

    @Test func codeStartsMonospacedAndProseDoesNot() {
        #expect(make(.text("func a() {\n    return 1\n}\n")).isMonospaced)
        #expect(!make(.text("Xin chào các bạn")).isMonospaced)
        let model = make()
        model.isMonospaced.toggle()
        #expect(model.isMonospaced)
    }

    @Test func aRichTextSaysItsFormattingWillBeLostAndOthersDoNot() {
        #expect(make(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8))).losesFormatting)
        #expect(!make(.text("Bảng giá")).losesFormatting)
        #expect(!make(.link(URL(string: "https://example.com")!)).losesFormatting)
    }

    // MARK: Saving

    @Test func savingAsNewAsksTheHistoryAndClosesWhenItWorked() {
        let model = make()
        model.text = "Xin chào bạn"
        model.save(.saveAsNew)
        #expect(saves.count == 1 && saves[0].mode == .saveAsNew && saves[0].text == "Xin chào bạn")
        #expect(closed == 1)
        #expect(model.notice == nil)
    }

    @Test func replacingAsksForReplace() {
        let model = make()
        model.text = "Xin chào bạn"
        model.save(.replace)
        #expect(saves.count == 1 && saves[0].mode == .replace)
        #expect(closed == 1)
    }

    @Test func nothingIsSavedWithoutAChangeOrWithBlankWords() {
        let model = make()
        model.save(.saveAsNew)
        model.text = " "
        model.save(.replace)
        #expect(saves.isEmpty && closed == 0)
    }

    @Test func aRefusalKeepsTheEditorOpenAndSaysWhy() {
        let model = make()
        model.text = "Xin chào bạn"
        answer = .duplicate(UUID())
        model.save(.replace)
        #expect(closed == 0)
        #expect(model.notice?.contains("Lưu thành mục mới") == true)
        // Typing again clears it, and saving as new is still there.
        model.text = "Xin chào bạn ơi"
        #expect(model.notice == nil)
        answer = .saved(UUID())
        model.save(.saveAsNew)
        #expect(closed == 1)
    }

    @Test func everyRefusalHasItsOwnWords() {
        func notice(for outcome: ClipboardEditOutcome) -> String? {
            let model = make()
            model.text = "khác"
            answer = outcome
            model.save(.replace)
            return model.notice
        }
        let all = [
            notice(for: .unchanged), notice(for: .blank), notice(for: .tooLarge), notice(for: .missing),
            notice(for: .locked), notice(for: .notEditable), notice(for: .duplicate(UUID())), notice(for: .stopped),
        ]
        #expect(all.allSatisfy { $0 != nil && $0?.isEmpty == false })
        #expect(Set(all.compactMap(\.self)).count >= 6)
        #expect(closed == 0)
    }

    // MARK: Cancelling

    @Test func cancellingWithoutChangesClosesAtOnce() {
        let model = make()
        model.cancel()
        #expect(closed == 1)
        #expect(!model.isConfirmingDiscard)
    }

    @Test func cancellingWithChangesAsksFirstAndKeepsTheWords() {
        let model = make()
        model.text = "Xin chào bạn"
        model.cancel()
        #expect(closed == 0)
        #expect(model.isConfirmingDiscard)
        #expect(model.text == "Xin chào bạn")

        model.keepEditing()
        #expect(!model.isConfirmingDiscard && closed == 0)
        #expect(model.text == "Xin chào bạn")
    }

    @Test func discardingClosesWithoutSaving() {
        let model = make()
        model.text = "Xin chào bạn"
        model.cancel()
        model.discard()
        #expect(closed == 1)
        #expect(saves.isEmpty)
        #expect(!model.isConfirmingDiscard)
    }

    @Test func theWindowMayCloseOnlyWhenThereIsNothingToLose() {
        let model = make()
        #expect(model.windowShouldClose())
        model.text = "khác"
        #expect(!model.windowShouldClose())
        #expect(model.isConfirmingDiscard)
        // The close button does not call `close` itself: the window closes when this answers yes, or when the user discards.
        #expect(closed == 0)
    }

    @Test func putTheWordsBackAndTheWindowClosesAgainWithoutAsking() {
        let model = make()
        model.text = "khác"
        model.text = "Xin chào"
        #expect(model.windowShouldClose())
        model.cancel()
        #expect(closed == 1)
    }

    @Test func closingIsOnlyEverToldOnce() {
        let model = make()
        model.cancel()
        model.cancel()
        model.discard()
        model.itemGone()
        #expect(closed == 1)
    }

    // MARK: The item going away

    @Test func whenTheItemIsGoneTheEditorClosesAtOnceAndForgetsItsWords() {
        let model = make()
        model.text = "bí mật đã sửa dở"
        model.itemGone()
        #expect(closed == 1)
        // Nothing to ask about: the words are dropped, as a locked board's must be.
        #expect(model.text.isEmpty && model.originalText.isEmpty)
        #expect(!model.isConfirmingDiscard)
        #expect(saves.isEmpty)
    }

    // MARK: Keys

    func key(_ keyCode: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> Keys.Key {
        Keys.Key(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    @Test func escapeAndCommandWCancelAndNothingElseDoes() {
        #expect(ClipboardEditorKeys.command(for: key(53, "\u{1B}"), hasMarkedText: false) == .cancel)
        #expect(ClipboardEditorKeys.command(for: key(13, "w", modifiers: .command), hasMarkedText: false) == .cancel)
        // Caps Lock, Fn and the numpad flag change nothing.
        #expect(ClipboardEditorKeys.command(for: key(53, "\u{1B}", modifiers: .capsLock), hasMarkedText: false) == .cancel)
        #expect(ClipboardEditorKeys.command(for: key(13, "w", modifiers: [.command, .capsLock]), hasMarkedText: false) == .cancel)
        for other in [
            key(13, "w"), key(13, "w", modifiers: [.command, .shift]), key(13, "w", modifiers: [.command, .option]),
            key(53, "\u{1B}", modifiers: .shift), key(53, "\u{1B}", modifiers: .command), key(36, "\r"), key(1, "s", modifiers: .command),
            key(49, " "),
        ] {
            #expect(ClipboardEditorKeys.command(for: other, hasMarkedText: false) == nil, "\(other)")
        }
    }

    @Test func escapeWhileAnInputMethodIsComposingIsTheMethods() {
        #expect(ClipboardEditorKeys.command(for: key(53, "\u{1B}"), hasMarkedText: true) == nil)
        // ⌘W is not part of a composition: it still closes.
        #expect(ClipboardEditorKeys.command(for: key(13, "w", modifiers: .command), hasMarkedText: true) == .cancel)
    }

    @Test func aHeldKeyIsOnlyAskedOnce() {
        var held = key(53, "\u{1B}")
        held.isRepeat = true
        #expect(ClipboardEditorKeys.command(for: held, hasMarkedText: false) == .ignore)
    }
}
