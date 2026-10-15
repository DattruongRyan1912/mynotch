import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// Fix round 1: the words typed in an editor outlive the item they came from, unless that item was a secret of a board that locked.
/// Pruning, deleting, clearing and stopping must not drop them silently, the idle lock must not close a board under an editor in
/// use, and a replace or a save must not leave stale copies or pin the wrong items.
extension ClipboardEditorModuleTests {
    /// The settings that make the oldest item the next to be pruned: the smallest history there is.
    func limitTheHistoryToTheSmallest() throws {
        let (settings, keys) = try settings()
        settings.set(ClipboardSettingKeys.historyLimitRange.lowerBound, for: keys.historyLimit)
    }

    /// Copies enough other texts for the history to go over its limit and drop the oldest unpinned item.
    func copyUntilTheOldestIsPruned() {
        for number in 0..<ClipboardSettingKeys.historyLimitRange.lowerBound { copy("mục thường số \(number)") }
    }

    // MARK: The item goes away while the editor is open

    @Test func pruningTheItemKeepsTheEditorTheWordsAndASaveAsNew() async throws {
        try limitTheHistoryToTheSmallest()
        await start()
        copy("bản nháp đầu tiên")
        let id = try item("bản nháp đầu tiên").id
        let model = try openEditor(on: "bản nháp đầu tiên")
        model.text = "bản nháp đầu tiên, đã sửa dài thêm"

        copyUntilTheOldestIsPruned()

        #expect(!history.items.contains { $0.id == id })
        #expect(editorWindow.isOpen(id))
        #expect(model.text == "bản nháp đầu tiên, đã sửa dài thêm")
        // The words are all that is left of it: saving as new brings them back.
        model.save(.saveAsNew)
        #expect(history.items.first?.content == .text("bản nháp đầu tiên, đã sửa dài thêm"))
        #expect(!editorWindow.isOpen(id))
    }

    @Test func deletingTheItemKeepsTheEditorAndTheWords() async throws {
        await start()
        copy("Xin chào")
        let gone = try item("Xin chào")
        let model = try openEditor(on: "Xin chào")
        model.text = "Xin chào các bạn"

        module.delete(gone)

        #expect(editorWindow.isOpen(gone.id))
        #expect(model.text == "Xin chào các bạn")
        #expect(!model.isConfirmingDiscard)
        model.save(.saveAsNew)
        #expect(history.items.map(\.content.plainText) == ["Xin chào các bạn"])
    }

    @Test func clearingTheHistoryKeepsTheEditorAndTheWords() async throws {
        await start()
        copy("Xin chào")
        let id = try item("Xin chào").id
        let model = try openEditor(on: "Xin chào")
        model.text = "Xin chào các bạn"

        module.clearHistory(.all)

        #expect(history.items.isEmpty)
        #expect(editorWindow.isOpen(id))
        model.save(.saveAsNew)
        #expect(history.items.map(\.content.plainText) == ["Xin chào các bạn"])
    }

    @Test func aSecretOfAnOriginalThatIsGoneStaysASecretWhenItsWordsAreSavedAsNew() async throws {
        await start()
        copy("mã dự phòng 77")
        module.update { history in
            history.items[0].sensitive = true
            return []
        }
        let gone = try item("mã dự phòng 77")
        let model = try openEditor(on: "mã dự phòng 77")
        model.text = "mã dự phòng 78"
        module.delete(gone)

        model.save(.saveAsNew)

        #expect(try item("mã dự phòng 78").sensitive == true)
    }

    @Test func replacingAnOriginalThatIsGoneIsRefusedAndSavingAsNewIsTheWay() async throws {
        await start()
        copy("Xin chào")
        let gone = try item("Xin chào")
        let model = try openEditor(on: "Xin chào")
        model.text = "Xin chào các bạn"
        module.delete(gone)

        model.save(.replace)

        #expect(history.items.isEmpty)
        #expect(editorWindow.isOpen(gone.id))
        #expect(model.notice != nil)
    }

    // MARK: Stopping

    @Test func stoppingSavesTheEditedWordsAsANewItemBeforeTheHistoryIsWritten() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")
        model.text = "Xin chào các bạn"

        await stop()

        #expect(!editorWindow.isOpen(model.itemID))
        #expect(module.editors.open.isEmpty)
        #expect(reload().items.compactMap(\.content.plainText).sorted() == ["Xin chào", "Xin chào các bạn"])
    }

    @Test func stoppingWithAnEditorThatWasNotEditedAddsNothing() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")

        await stop()

        #expect(!editorWindow.isOpen(model.itemID))
        #expect(reload().items.map(\.content.plainText) == ["Xin chào"])
    }

    @Test func stoppingDoesNotBringBackAnItemTheUserDeletedWhileItsEditorWasOpen() async throws {
        await start()
        copy("Xin chào")
        let gone = try item("Xin chào")
        _ = try openEditor(on: "Xin chào")
        module.delete(gone)

        await stop()

        #expect(reload().items.isEmpty)
    }

    @Test func stoppingWithAnEditorOfASecretSavesNothingOfItsWords() async throws {
        await start()
        _ = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-đang gõ dở"

        await stop()

        #expect(!editorWindow.isOpen(model.itemID))
        #expect(model.text.isEmpty)
        #expect(!reload().items.contains { $0.content.plainText?.contains("đang gõ dở") == true })
        #expect(!reload().items.contains { $0.content.plainText?.contains(Self.secretText) == true })
    }

    // MARK: The idle lock under an editor in use

    @Test func typingInTheEditorOfAnOpenBoardsItemKeepsTheBoardOpen() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)

        for minute in 1...4 {
            harness.scheduler.advance(by: .seconds(60))
            system.now = system.now.addingTimeInterval(60)
            model.text += "\(minute)"
        }
        harness.scheduler.advance(by: .seconds(60))
        // Five idle minutes have gone by since the board was opened, but not since the last key.
        #expect(try #require(history.boards.first { $0.id == board }).isLocked == false)

        harness.scheduler.advance(by: .seconds(301))
        #expect(try #require(history.boards.first { $0.id == board }).isLocked)
    }

    @Test func typingInTheEditorOfAnOrdinaryItemDoesNotKeepABoardOpen() async throws {
        await start()
        copy("một mục thường")
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: "một mục thường")
        harness.scheduler.advance(by: .seconds(200))
        system.now = system.now.addingTimeInterval(200)
        model.text += " thêm"
        harness.scheduler.advance(by: .seconds(101))
        #expect(try #require(history.boards.first { $0.id == board }).isLocked)
    }

    @Test func keysInQuickSuccessAreOneNoteOfActivity() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text += "a"
        harness.scheduler.advance(by: .seconds(5))
        system.now = system.now.addingTimeInterval(5)
        // Within ten seconds of the last note: the idle time is not started again.
        model.text += "b"
        harness.scheduler.advance(by: .seconds(296))
        #expect(try #require(history.boards.first { $0.id == board }).isLocked)
    }

    @Test func aLockThatDropsUnsavedWordsSaysSoWithoutSayingWhat() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-đang gõ dở"
        let toasts = harness.presenter.toastCount

        #expect(module.relockBoard(board))

        #expect(harness.presenter.toastCount == toasts + 1)
        // And the window says it too, where the user is looking: it stays, empty, with the notice.
        #expect(editorWindow.isOpen(model.itemID))
        #expect(model.isDroppedOnLock)
    }

    @Test func anEditorThatShowsTheLockNoticeIsNotClosedByTheNextChangeOfTheHistory() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-đang gõ dở"
        #expect(module.relockBoard(board))
        let toasts = harness.presenter.toastCount

        copy("một mục thường")
        copy("một mục khác")

        #expect(editorWindow.isOpen(model.itemID))
        #expect(model.isDroppedOnLock)
        #expect(module.editors.open.count == 1)
        // Said once, not at every change of the history.
        #expect(harness.presenter.toastCount == toasts)
    }

    @Test func stoppingClosesAnEditorThatShowsTheLockNotice() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-đang gõ dở"
        #expect(module.relockBoard(board))

        await stop()

        #expect(!editorWindow.isOpen(model.itemID))
        #expect(module.editors.open.isEmpty)
        #expect(!reload().items.contains { $0.content.plainText?.contains("đang gõ dở") == true })
    }

    @Test func afterTheBoardIsUnlockedEditingTheItemOpensALiveEditorWithItsWords() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let id = try item(Self.secretText).id
        let dropped = try openEditor(on: Self.secretText)
        dropped.text += "-đang gõ dở"
        #expect(module.relockBoard(board))
        #expect(dropped.isDroppedOnLock && editorWindow.isOpen(id))
        try await module.unlockBoard(board, credential: .password(Self.password))

        #expect(module.edit(try item(Self.secretText)))

        // Not the empty window with the lock caption: the old one is closed and a new editor shows the item's words.
        let fresh = try #require(editorWindow.models[id])
        #expect(fresh !== dropped)
        #expect(editorWindow.showCount == 2)
        #expect(editorWindow.isOpen(id))
        #expect(fresh.text == Self.secretText && fresh.originalText == Self.secretText)
        #expect(!fresh.isDroppedOnLock && !fresh.hasChanges)
        #expect(fresh.isProtected)
        #expect(module.editors.open.count == 1 && module.editors.open[id] === fresh)
        #expect(state.historyObserverCount == 1)
        // It works: a replace goes into the item, which is back in its board.
        fresh.text = Self.secretText + "-ĐÃ-SỬA"
        fresh.save(.replace)
        #expect(try item(Self.secretText + "-ĐÃ-SỬA").id == id)
        #expect(!editorWindow.isOpen(id))
    }

    @Test func anEditorThatIsLiveIsStillOnlyBroughtForwardWhenEditedAgain() async throws {
        await start()
        copy("Xin chào")
        let model = try openEditor(on: "Xin chào")
        model.text = "Xin chào các bạn"

        #expect(module.edit(try item("Xin chào")))

        #expect(editorWindow.showCount == 1 && editorWindow.frontCount == 1)
        #expect(editorWindow.models[model.itemID] === model)
        #expect(model.text == "Xin chào các bạn")
    }

    @Test func aWipeIsNotTypingSoLockingOneBoardDoesNotKeepAnotherOpenLonger() async throws {
        await start()
        let first = try await openBoard(holding: ["bí mật của hai"])
        copy("bí mật của ba")
        let second = try #require(module.createBoard(named: "Két ba"))
        module.pin(try item("bí mật của ba"), to: second)
        try await module.lockBoard(second, setup: .password(Self.password))
        try await module.unlockBoard(second, credential: .password(Self.password))
        let model = try openEditor(on: "bí mật của hai")
        model.text += "x"
        // Both boards were opened about now; 200 s later the first locks under the editor, with unsaved words.
        harness.scheduler.advance(by: .seconds(200))
        system.now = system.now.addingTimeInterval(200)
        #expect(module.relockBoard(first))

        // The wipe is not the user working in the other board: its idle time runs out when it was meant to.
        harness.scheduler.advance(by: .seconds(150))
        #expect(try #require(history.boards.first { $0.id == second }).isLocked)
    }

    @Test func aLockWithNothingUnsavedSaysNothing() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        _ = try openEditor(on: Self.secretText)
        let toasts = harness.presenter.toastCount

        #expect(module.relockBoard(board))

        #expect(harness.presenter.toastCount == toasts)
    }

    // MARK: An item that is pinned or unpinned while it is edited

    @Test func anItemPinnedToAnOpenBoardWhileItIsEditedIsWipedWhenTheBoardLocks() async throws {
        await start()
        copy("một mục thường")
        let board = try await openBoard(holding: ["mã số 99"])
        let model = try openEditor(on: "một mục thường")
        module.pin(try item("một mục thường"), to: board)
        model.text = "một mục thường, giờ là bí mật"

        #expect(module.relockBoard(board))

        #expect(model.text.isEmpty && model.isDroppedOnLock)
        #expect(editorWindow.isOpen(model.itemID))
    }

    @Test func afterTheLockIsRemovedTheItemIsOrdinaryAgainAndItsWordsAreKept() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let secret = try item(Self.secretText)
        let model = try openEditor(on: Self.secretText)
        try await module.removeLock(from: board)
        // Any change tells the editor that its item is not protected any more.
        copy("một mục thường")
        model.text = Self.secretText + "-đã sửa"

        module.delete(secret)

        #expect(editorWindow.isOpen(secret.id))
        #expect(model.text == Self.secretText + "-đã sửa")
    }

    // MARK: What a replace leaves behind

    @Test func aReplacedItemTakesTheCurrentDateAndMovesToTheTop() async throws {
        await start()
        copy("một")
        copy("hai")
        copy("ba")
        let original = try item("một")
        let model = try openEditor(on: "một")
        system.now = system.now.addingTimeInterval(3_600)

        model.text = "một nghìn"
        model.save(.replace)

        #expect(history.items.map(\.content.plainText) == ["một nghìn", "ba", "hai"])
        let replaced = try item("một nghìn")
        #expect(replaced.id == original.id)
        #expect(replaced.copiedAt == system.now)
        #expect(replaced.sourceBundleID == "com.apple.Safari" && replaced.isEdited)
    }

    @Test func theCopyStackPastesTheNewWordsAfterAReplace() async throws {
        await start()
        module.startStack()
        copy("một")
        copy("hai")
        #expect(state.stack.entries.map(\.item.content.plainText) == ["một", "hai"])
        let model = try openEditor(on: "một")

        model.text = "một nghìn"
        model.save(.replace)

        #expect(state.stack.entries.map(\.item.content.plainText) == ["một nghìn", "hai"])
    }

    @Test func aStaleCardOpensTheEditorOnTheWordsThatAreThereNow() async throws {
        await start()
        copy("Xin chào")
        let stale = try item("Xin chào")
        module.update { history in
            _ = history.applyEdit(to: stale.id, content: .text("Xin chào đã sửa nơi khác"), mode: .replace, at: system.now)
            return []
        }

        #expect(module.edit(stale))

        #expect(editorWindow.models[stale.id]?.text == "Xin chào đã sửa nơi khác")
    }

    @Test func aReplacedItemOfAnOpenBoardIsInTheVaultAfterLockingAndOpeningAgain() async throws {
        await start()
        let board = try await openBoard(holding: [Self.secretText])
        let model = try openEditor(on: Self.secretText)
        model.text = Self.secretText + "-ĐÃ-SỬA"
        model.save(.replace)

        #expect(module.relockBoard(board))
        #expect(history.items.isEmpty)
        try await module.unlockBoard(board, credential: .password(Self.password))

        let back = try item(Self.secretText + "-ĐÃ-SỬA")
        #expect(back.isEdited)
        #expect(history.boards.first { $0.id == board }?.itemIDs.contains(back.id) == true)
    }
}
