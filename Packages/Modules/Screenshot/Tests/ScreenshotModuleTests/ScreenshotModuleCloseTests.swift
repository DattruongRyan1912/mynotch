import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// What the editor's close alert does when it is answered, with an editor that has no window.
extension ScreenshotModuleTests {
    /// An editor for `record` with a redaction drawn on it, held by `controller` and never shown.
    func editedSession(
        _ controller: MarkupEditorWindowController, for record: CaptureRecord
    ) async throws -> MarkupEditorWindowController.Session {
        let source = try #require(await module.editorSource(for: record))
        let session = controller.makeSession(record, source: source)
        session.model.select(.redact)
        session.model.dragChanged(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 40), pixelsPerPoint: 1)
        session.model.dragEnded(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 30, y: 40), pixelsPerPoint: 1)
        #expect(session.model.document.hasEdits)
        return session
    }

    @Test(.timeLimit(.minutes(1))) func saveInTheCloseAlertSavesAndCopiesLikeTheSaveButton() async throws {
        let record = try await capturedRecord()
        let controller = MarkupEditorWindowController(module: module)
        let session = try await editedSession(controller, for: record)
        let copies = pasteboard.images.count
        let toasts = harness.presenter.toastCount

        controller.answerClose(.save, for: record.id)
        await waitUntil { session.closesWithoutAsking }

        // Saved, then closed without asking again.
        #expect(session.closesWithoutAsking)
        #expect(module.state.records.first?.hasMarkup == true)
        #expect(session.savedDocument == session.model.document)
        // Copied, as an ordinary copy, once, with the one toast that Lưu gives.
        #expect(pasteboard.images.count == copies + 1)
        let copied = try #require(pasteboard.images.last)
        #expect(!copied.markedAsOwn)
        #expect(try Bitmap(copied.image).pixel(0, 0) == visibleBitmap(of: record).pixel(0, 0))
        #expect(harness.presenter.toastCount == toasts + 1)
    }

    @Test(.timeLimit(.minutes(1))) func withTheSettingOffSaveInTheCloseAlertCopiesNothing() async throws {
        let record = try await capturedRecord()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.copyWhenDone)
        let controller = MarkupEditorWindowController(module: module)
        let session = try await editedSession(controller, for: record)
        let copies = pasteboard.images.count

        controller.answerClose(.save, for: record.id)
        await waitUntil { session.closesWithoutAsking }

        #expect(session.closesWithoutAsking)
        #expect(module.state.records.first?.hasMarkup == true)
        #expect(pasteboard.images.count == copies)
    }

    @Test(.timeLimit(.minutes(1))) func aSaveThatFailsLeavesTheEditorOpen() async throws {
        let record = try await capturedRecord()
        let controller = MarkupEditorWindowController(module: module)
        let session = try await editedSession(controller, for: record)
        module.delete(record)
        let copies = pasteboard.images.count

        controller.answerClose(.save, for: record.id)
        await waitUntil { !session.isSaving }

        #expect(!session.closesWithoutAsking)
        #expect(pasteboard.images.count == copies)
    }

    @Test func discardClosesWithoutSavingOrCopying() async throws {
        let record = try await capturedRecord()
        let controller = MarkupEditorWindowController(module: module)
        let session = try await editedSession(controller, for: record)
        let copies = pasteboard.images.count
        let before = try pngData(of: record)

        controller.answerClose(.discard, for: record.id)

        #expect(session.closesWithoutAsking)
        #expect(module.state.records.first?.hasMarkup == false)
        #expect(try pngData(of: record) == before)
        #expect(pasteboard.images.count == copies)
    }

    @Test func keepEditingChangesNothing() async throws {
        let record = try await capturedRecord()
        let controller = MarkupEditorWindowController(module: module)
        let session = try await editedSession(controller, for: record)
        let copies = pasteboard.images.count

        controller.answerClose(.keepEditing, for: record.id)

        #expect(!session.closesWithoutAsking)
        #expect(!session.isSaving)
        #expect(module.state.records.first?.hasMarkup == false)
        #expect(pasteboard.images.count == copies)
        #expect(session.model.document.hasEdits)
    }

    @Test func anAnswerForAnEditorThatIsGoneDoesNothing() async throws {
        let record = try await capturedRecord()
        let controller = MarkupEditorWindowController(module: module)
        let copies = pasteboard.images.count

        controller.answerClose(.save, for: record.id)

        #expect(pasteboard.images.count == copies)
    }
}
