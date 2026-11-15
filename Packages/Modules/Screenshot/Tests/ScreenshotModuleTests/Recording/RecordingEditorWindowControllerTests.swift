import AppKit
import Foundation
import Testing
@testable import ScreenshotModule

/// No window is ever made or shown: the sessions are registered without one, as the markup editor's tests do.
@Suite(.serialized) struct RecordingEditorWindowControllerTests {
    func controller(_ editor: EditorFixture) -> RecordingEditorWindowController {
        RecordingEditorWindowController(pasteboard: editor.pasteboard, exportDirectory: editor.exports.url, reveal: { _ in })
    }

    @Test func aSessionLoadsTheRecordingAndIsKeptByItsFolder() async throws {
        let editor = try await EditorFixture(start: false)
        let controller = controller(editor)

        let session = try controller.makeSession(folder: editor.folder.standardizedFileURL)
        #expect(controller.openFolders == [editor.folder.standardizedFileURL])
        #expect(session.window == nil)
        #expect(abs(session.model.duration - 7) < 0.05)
        // The preview is on its way.
        await session.startTask?.value
        #expect(session.model.preview != nil)
        controller.closeAll()
        #expect(controller.openFolders.isEmpty)
    }

    @Test func aRecordingStillBeingRecordedGetsNoSession() async throws {
        let editor = try await EditorFixture(start: false)
        var project = try editor.savedProject()
        project.status = .recording
        try project.write(to: editor.folder)
        let controller = controller(editor)

        do {
            _ = try controller.makeSession(folder: editor.folder.standardizedFileURL)
            Issue.record("a session was made")
        } catch {
            #expect(error == .stillRecording)
        }
        #expect(controller.openFolders.isEmpty)
    }

    @Test func aFolderThatIsNotARecordingGetsNoSession() async throws {
        let editor = try await EditorFixture(start: false)
        let empty = try TestFolder("editor-empty")
        let controller = controller(editor)
        do {
            _ = try controller.makeSession(folder: empty.url)
            Issue.record("a session was made")
        } catch {
            guard case .unreadable = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(controller.openFolders.isEmpty)
    }

    @Test func closingEverythingCancelsAnExportThatIsRunningAndLeavesNoFile() async throws {
        let editor = try await EditorFixture(start: false)
        let controller = controller(editor)
        let session = try controller.makeSession(folder: editor.folder.standardizedFileURL)
        let model = session.model
        model.startExport()
        #expect(model.isExporting)

        controller.closeAll()
        await model.waitForExport()

        #expect(controller.openFolders.isEmpty)
        #expect(model.exportState == .idle)
        #expect(try editor.exportedFiles().isEmpty)
        #expect(editor.pasteboard.files.isEmpty)
    }

    @Test func onlyTheSecondButtonOfTheCloseAlertCancelsTheExport() {
        #expect(RecordingEditorClosing.alertButtons == ["Tiếp tục xuất", "Huỷ xuất và đóng"])
        #expect(RecordingEditorClosing.choice(for: .alertFirstButtonReturn) == .keepExporting)
        #expect(RecordingEditorClosing.choice(for: .alertSecondButtonReturn) == .cancelAndClose)
        #expect(RecordingEditorClosing.choice(for: .alertThirdButtonReturn) == .keepExporting)
        #expect(RecordingEditorClosing.choice(for: .cancel) == .keepExporting)
        #expect(RecordingEditorClosing.choice(for: .stop) == .keepExporting)
    }
}
