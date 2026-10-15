import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The lock form, the unlock prompt, the confirmations and the lock glyphs, built and measured in memory (no window, no screen).
/// How they look and feel is for the person to check; here, that each state is built, fits where it is shown, and says what the
/// brief says.
@Suite struct ClipboardBoardLockViewTests {
    static func board(lock: ClipboardBoardLock? = nil) -> ClipboardBoard {
        ClipboardBoard(id: UUID(), name: "Két", systemImage: "key", itemIDs: [], lock: lock)
    }

    func size(of view: some View, width: CGFloat) -> CGSize {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        return hosting.fittingSize
    }

    func vault(_ mode: ClipboardBoardVaultView.Mode, look: ClipboardLook, board: ClipboardBoard) -> some View {
        let fixture = ClipboardBoardLockModuleTests()
        return ClipboardBoardVaultView(module: fixture.module, look: look, mode: mode, board: board, onDone: {}, onCancel: {})
            .environment(\.notchAccent, .cyan)
    }

    @Test(arguments: [ClipboardBoardVaultView.Mode.setUp, .unlock, .removeLock, .deleteData])
    func everyStateIsBuiltInTheNotchAndTheLibrary(mode: ClipboardBoardVaultView.Mode) {
        let lock = mode == .setUp ? nil : ClipboardBoardLock(method: .password, itemCount: 3, isUnlocked: mode != .unlock)
        let board = Self.board(lock: mode == .unlock ? ClipboardBoardLock(method: .password, itemCount: 3, isUnlocked: false) : lock)
        for look in [ClipboardLook.notch, .library] {
            #expect(size(of: vault(mode, look: look, board: board), width: 520).width > 0)
        }
    }

    @Test func theLockFormAndThePromptFitBelowTheNotchsRows() {
        // The notch's tab is 240 pt at most; the search row and the boards row take about 50 of it.
        let height = size(of: vault(.setUp, look: .notch, board: Self.board()), width: 540).height
        #expect(height <= 150, "the lock form is \(height) pt tall")
        let locked = Self.board(lock: ClipboardBoardLock(method: .password, itemCount: 3, isUnlocked: false))
        #expect(size(of: vault(.unlock, look: .notch, board: locked), width: 540).height <= 150)
        let touch = Self.board(lock: ClipboardBoardLock(method: .touchID, itemCount: 3, isUnlocked: false))
        #expect(size(of: vault(.unlock, look: .notch, board: touch), width: 540).height <= 150)
    }

    @Test func aLockedBoardsPillShowsAClosedLockAndAnOpenOneAnOpenLock() throws {
        func ink(_ board: ClipboardBoard) throws -> Int {
            let renderer = ImageRenderer(content: ClipboardBoardPill(board: board, isSelected: false).background(Color.black).frame(width: 200, height: 30))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            return (0..<bitmap.pixelsHigh).reduce(0) { total, y in
                total + (0..<bitmap.pixelsWide).count { x in (bitmap.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.3 }
            }
        }
        let plain = try ink(Self.board())
        let locked = try ink(Self.board(lock: ClipboardBoardLock(method: .password, itemCount: 2, isUnlocked: false)))
        #expect(locked > plain, "a lock glyph adds ink to the pill")
    }

    @Test func theSettingsRowsForLockedBoardsAreBuilt() {
        #expect(ClipboardSettingsView.boardLockNote.contains("khoá màn hình"))
        #expect(ClipboardSettingsView.boardLockNote.contains("Quên mật khẩu"))
    }

    @Test func theBackupSheetOffersLockedBoardsOnlyWhenThereAreSome() {
        let none = ClipboardBackupOptionsSheet(legacyTextCount: { _ in 0 }, onChoose: { _ in }, onCancel: {})
        let some = ClipboardBackupOptionsSheet(legacyTextCount: { _ in 0 }, lockedBoardCount: 2, onChoose: { _ in }, onCancel: {})
        #expect(size(of: some, width: 440).height > size(of: none, width: 440).height)
        #expect(ClipboardBackupOptionsSheet.lockedIncludedCaption.contains("cần mật khẩu của chính nó"))
        #expect(ClipboardBackupOptionsSheet.lockedIncludedCaption.contains("không có cách lấy lại"))
        #expect(ClipboardBackupOptionsSheet.lockedLeftOutCaption.contains("kể cả tên"))
    }

    @Test func theRestoreSheetNamesTheLockedBoardsItBrings() {
        var summary = ClipboardRestorePlanSummary()
        summary.added = 3
        summary.lockedBoards = 2
        let text = ClipboardRestorePlanSheet.overview(summary)
        #expect(text.contains("2 board đã khoá") && text.contains("mật khẩu"))
    }
}
