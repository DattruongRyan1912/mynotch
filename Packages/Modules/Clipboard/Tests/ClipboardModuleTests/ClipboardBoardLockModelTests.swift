import Foundation
import Testing
@testable import ClipboardModule

/// The decisions of the lock form, the unlock prompt and the two confirmations, with the module replaced by closures that record
/// what they were asked.
@Suite final class ClipboardBoardLockModelTests {
    /// What the model asked of the module, and what the module will answer.
    final class Calls {
        var locks: [String] = []
        var unlocks: [String] = []
        var deletions = 0
        var removals = 0
        var failure: (any Error)?
    }

    let calls = Calls()

    func name(_ setup: ClipboardLockSetup) -> String {
        switch setup {
        case .password(let password): "password:\(password)"
        case .touchID: "touchID"
        }
    }

    func name(_ credential: ClipboardUnlockCredential) -> String {
        switch credential {
        case .password(let password): "password:\(password)"
        case .touchID: "touchID"
        }
    }

    func model(method: ClipboardLockMethod? = nil, count: Int = 3, touchID: Bool = true) -> ClipboardBoardLockModel {
        let calls = calls
        let model = ClipboardBoardLockModel(
            boardName: "Két", method: method, itemCount: count, touchIDAvailable: touchID,
            lock: { setup in
                calls.locks.append(self.name(setup))
                if let failure = calls.failure { throw failure }
            },
            unlock: { credential in
                calls.unlocks.append(self.name(credential))
                if let failure = calls.failure { throw failure }
            },
            deleteData: { calls.deletions += 1 },
            removeLock: {
                calls.removals += 1
                if let failure = calls.failure { throw failure }
            }
        )
        return model
    }

    // MARK: Setting a password

    @Test func aPasswordHasToBeLongEnoughAndTypedTwice() {
        let model = model()
        #expect(!model.canLockWithPassword && model.problem == nil)

        model.password = "ngắn"
        #expect(model.problem == ClipboardBoardLockModel.tooShort && !model.canLockWithPassword)

        model.password = "mật khẩu đủ dài"
        #expect(model.problem == nil && !model.canLockWithPassword)

        model.confirmation = "mật khẩu đủ dà"
        #expect(model.problem == ClipboardBoardLockModel.differ && !model.canLockWithPassword)

        model.confirmation = "mật khẩu đủ dài"
        #expect(model.problem == nil && model.canLockWithPassword)
    }

    @Test func lockingWithAPasswordAsksTheModuleAndEmptiesTheFields() async {
        let model = model()
        var done = 0
        model.onDone = { done += 1 }
        model.password = "mật khẩu đủ dài"
        model.confirmation = "mật khẩu đủ dài"

        await model.lockWithPassword()

        #expect(calls.locks == ["password:mật khẩu đủ dài"])
        #expect(done == 1 && model.status == .idle)
        #expect(model.password.isEmpty && model.confirmation.isEmpty)
    }

    @Test func aPasswordThatDoesNotQualifyIsNeverSent() async {
        let model = model()
        model.password = "ngắn"
        model.confirmation = "ngắn"
        await model.lockWithPassword()
        model.password = "mật khẩu đủ dài"
        model.confirmation = "khác hẳn"
        await model.lockWithPassword()
        #expect(calls.locks.isEmpty)
    }

    @Test func lockingWithTouchIDAsksForNoPassword() async {
        let model = model()
        await model.lockWithTouchID()
        #expect(calls.locks == ["touchID"])
    }

    @Test func withoutTouchIDTheOptionIsHiddenWithTheReasonAndNeverAsked() async {
        let model = model(touchID: false)
        #expect(!model.showsTouchID)
        #expect(model.touchIDNote == "Touch ID cần bản MyNotch có hồ sơ ký; hiện dùng mật khẩu.")
        await model.lockWithTouchID()
        #expect(calls.locks.isEmpty)
        let available = self.model()
        #expect(available.showsTouchID && available.touchIDNote == ClipboardBoardLockModel.touchIDNote)
    }

    @Test func aFailureIsShownAndKeepsWhatWasTyped() async {
        let model = model()
        calls.failure = ClipboardVaultError.keychain(-34018)
        model.password = "mật khẩu đủ dài"
        model.confirmation = "mật khẩu đủ dài"
        var done = 0
        model.onDone = { done += 1 }

        await model.lockWithPassword()

        #expect(model.failureMessage == ClipboardVaultError.keychain(-34018).errorDescription)
        #expect(done == 0 && model.password == "mật khẩu đủ dài")
        // Typing again clears the message.
        model.password = "mật khẩu đủ dài!"
        #expect(model.failureMessage == nil)
    }

    @Test func dismissingTouchIDIsNotAnError() async {
        let model = model(method: .touchID)
        calls.failure = ClipboardVaultError.cancelled
        await model.unlockWithTouchID()
        #expect(model.status == .idle && model.failureMessage == nil)
    }

    // MARK: Opening

    @Test func anEmptyPasswordIsNotSentToUnlock() async {
        let model = model(method: .password)
        await model.unlockWithPassword()
        #expect(calls.unlocks.isEmpty)
        model.password = "x"
        await model.unlockWithPassword()
        #expect(calls.unlocks == ["password:x"])
    }

    @Test func aWrongPasswordIsShownAndTheFieldIsKept() async {
        let model = model(method: .password)
        calls.failure = ClipboardVaultError.wrongPassword
        model.password = "sai"
        await model.unlockWithPassword()
        #expect(model.failureMessage == "Sai mật khẩu.")
        #expect(model.password == "sai")
    }

    @Test func unlockingWithTouchID() async {
        let model = model(method: .touchID)
        var done = 0
        model.onDone = { done += 1 }
        await model.unlockWithTouchID()
        #expect(calls.unlocks == ["touchID"] && done == 1)
    }

    @Test func theModelKnowsWhatToShowOfALockedBoard() {
        let model = model(method: .password, count: 7)
        #expect(model.boardName == "Két" && model.itemCount == 7 && model.method == .password)
    }

    // MARK: Confirmations

    @Test func deletingTheDataNeedsAConfirmation() async {
        let model = model(method: .password)
        var done = 0
        model.onDone = { done += 1 }
        model.ask(.deleteData)
        #expect(model.confirming == .deleteData && calls.deletions == 0)
        model.cancelConfirmation()
        #expect(model.confirming == nil)

        model.ask(.deleteData)
        await model.confirm()
        #expect(calls.deletions == 1 && done == 1 && model.confirming == nil)
    }

    @Test func confirmingWithNothingAskedDoesNothing() async {
        let model = model()
        await model.confirm()
        #expect(calls.deletions == 0 && calls.removals == 0)
    }

    @Test func removingTheLockNeedsAConfirmationAndReportsAFailure() async {
        let model = model(method: .password)
        model.ask(.removeLock)
        calls.failure = ClipboardVaultError.stillLocked
        await model.confirm()
        #expect(calls.removals == 1)
        #expect(model.failureMessage == ClipboardVaultError.stillLocked.errorDescription)
        #expect(model.confirming == .removeLock)
        calls.failure = nil
        await model.confirm()
        #expect(calls.removals == 2 && model.confirming == nil)
    }

    // MARK: The words

    @Test func theLockFormSaysThereIsNoRecovery() {
        #expect(ClipboardBoardLockModel.noRecoveryWarning.contains("Không có cách khôi phục"))
        #expect(ClipboardBoardLockModel.noRecoveryWarning.contains("xoá được board"))
        #expect(ClipboardBoardLockModel.touchIDNote.contains("Keychain") && ClipboardBoardLockModel.touchIDNote.contains("sao lưu"))
    }

    @Test func thePromptsHaveStableIdentities() {
        let id = UUID()
        #expect(ClipboardVaultPrompt.lock(id).boardID == id && ClipboardVaultPrompt.deleteData(id).boardID == id)
        #expect(Set([ClipboardVaultPrompt.lock(id), .removeLock(id), .deleteData(id)].map(\.id)).count == 3)
    }

    // MARK: Through the module

    @Test func theModuleBuildsAModelThatLocksItsBoard() async throws {
        let fixture = ClipboardBoardLockModuleTests()
        await fixture.start()
        let board = try fixture.makeBoard(holding: [ClipboardBoardLockModuleTests.secretText])
        let model = fixture.module.lockModel(for: try fixture.board(board))
        model.password = ClipboardBoardLockModuleTests.password
        model.confirmation = ClipboardBoardLockModuleTests.password

        await model.lockWithPassword()

        #expect(try fixture.board(board).isLocked)
        let locked = fixture.module.lockModel(for: try fixture.board(board))
        #expect(locked.method == .password && locked.itemCount == 1)
        locked.password = "sai mật khẩu"
        await locked.unlockWithPassword()
        #expect(locked.failureMessage == "Sai mật khẩu.")
        locked.password = ClipboardBoardLockModuleTests.password
        await locked.unlockWithPassword()
        #expect(try !fixture.board(board).isLocked)
    }
}
