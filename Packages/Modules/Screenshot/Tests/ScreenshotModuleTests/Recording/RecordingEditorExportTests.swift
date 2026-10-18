import AVFoundation
import Foundation
import Testing
@testable import ScreenshotModule

/// Exporting from the editor: the file, the clipboard, what is shown meanwhile. One at a time, as the exporter's own tests.
@Suite(.serialized) struct RecordingEditorExportTests {
    @Test func exportingWritesTheEditedVideoAndPutsItsFileOnTheClipboardMarkedAsMyNotchsOwn() async throws {
        let editor = try await EditorFixture(edit: { $0.cuts = [CutRange(start: 1, end: 3)] })
        let model = editor.model!

        await model.export()

        guard case .finished(let result) = model.exportState else { Issue.record("not finished: \(model.exportState)"); return }
        let files = try editor.exportedFiles()
        #expect(files.count == 1 && files[0].hasSuffix(".mp4") && !files[0].hasPrefix("."))
        #expect(result.url.deletingLastPathComponent().standardizedFileURL == editor.exports.url.standardizedFileURL)
        // The file is the video as it is edited: 7 s with 2 s cut out.
        let probe = try await MediaProbe.read(result.url)
        #expect(abs(probe.duration - 5) < 0.15)
        #expect(probe.isPlayable && probe.videoCodec == kCMVideoCodecType_H264)
        #expect(editor.pasteboard.files.count == 1)
        #expect(editor.pasteboard.files.first?.url == result.url)
        #expect(editor.pasteboard.files.first?.markedAsOwn == true)
        #expect(editor.pasteboard.images.isEmpty && editor.pasteboard.texts.isEmpty)
        #expect(model.message == nil)
    }

    // MARK: Dating an export

    @Test func anExportIsDatedToTheSecondInTheProjectAndTheNextEditKeepsTheDate() async throws {
        let moment = Date(timeIntervalSince1970: 1_800_000_123.75)
        let editor = try await EditorFixture(now: { moment })
        let model = editor.model!
        let before = try editor.savedProject().exportedAt
        #expect(model.project.exportedAt == nil && before == nil)

        await model.export()

        let dated = Date(timeIntervalSince1970: 1_800_000_123)
        let saved = try editor.savedProject()
        #expect(model.project.exportedAt == dated && saved.exportedAt == dated)
        // The editor rewrites the whole file at every edit; a date written only beside the model would be gone after this.
        model.dismissExport()
        model.trimStart(to: 1)
        model.setClickEffect(false)
        let edited = try editor.savedProject()
        #expect(edited.exportedAt == dated && edited.cuts == [CutRange(start: 0, end: 1)] && !edited.clickEffect)
        model.undo()
        let undone = try editor.savedProject()
        #expect(undone.exportedAt == dated)
        // And a second editor on the same folder starts from it.
        let reopened = try RecordingEditorModel.load(folder: editor.folder, player: FakePreviewPlayer(), pasteboard: FakePasteboard(), exportDirectory: editor.exports.url)
        #expect(reopened.project.exportedAt == dated)
    }

    @Test func aLaterExportMovesTheDate() async throws {
        var moment = Date(timeIntervalSince1970: 1_800_000_000)
        let editor = try await EditorFixture(now: { moment })
        await editor.model.export()
        editor.model.dismissExport()
        moment = Date(timeIntervalSince1970: 1_800_086_400)

        await editor.model.export()

        let later = try editor.savedProject()
        #expect(later.exportedAt == Date(timeIntervalSince1970: 1_800_086_400))
    }

    @Test func anExportThatFailedOrWasCancelledDatesNothing() async throws {
        let failing = try await EditorFixture(start: false)
        try FileManager.default.removeItem(at: failing.folder.appending(path: "segment-002.mov"))
        await failing.model.export()
        let failedProject = try failing.savedProject()
        #expect(failing.model.project.exportedAt == nil && failedProject.exportedAt == nil)

        let cancelled = try await EditorFixture()
        cancelled.model.startExport()
        cancelled.model.cancelExport()
        await cancelled.model.export()
        let cancelledProject = try cancelled.savedProject()
        #expect(cancelled.model.project.exportedAt == nil && cancelledProject.exportedAt == nil)
    }

    @Test func theLevelThePersonChoseIsTheOneUsed() async throws {
        let editor = try await EditorFixture()
        editor.model.exportLevel = .high
        await editor.model.export()
        guard case .finished(let high) = editor.model.exportState else { Issue.record("not finished"); return }
        #expect(high.plan.audioBitrate == 192_000)

        editor.model.dismissExport()
        editor.model.exportLevel = .chat
        await editor.model.export()
        guard case .finished(let chat) = editor.model.exportState else { Issue.record("not finished"); return }
        #expect(chat.plan.audioBitrate == 128_000)
        #expect(chat.url != high.url)
        #expect(try editor.exportedFiles().count == 2)
    }

    @Test func aClipboardThatRefusesDoesNotLoseTheExportAndTheUserIsTold() async throws {
        let editor = try await EditorFixture()
        editor.pasteboard.succeeds = false
        await editor.model.export()
        guard case .finished(let result) = editor.model.exportState else { Issue.record("not finished"); return }
        #expect(FileManager.default.fileExists(atPath: result.url.path(percentEncoded: false)))
        #expect(editor.model.message?.contains("clipboard") == true)
    }

    @Test func anExportThatFailsSaysSoPutsNothingOnTheClipboardAndLeavesNoFile() async throws {
        let editor = try await EditorFixture(start: false)
        try FileManager.default.removeItem(at: editor.folder.appending(path: "segment-002.mov"))
        await editor.model.export()
        guard case .failed(let message) = editor.model.exportState else { Issue.record("did not fail: \(editor.model.exportState)"); return }
        #expect(message == RecordingCompositionError.missingFile("segment-002.mov").message)
        #expect(editor.pasteboard.files.isEmpty)
        #expect(try editor.exportedFiles().isEmpty)
        editor.model.dismissExport()
        #expect(editor.model.exportState == .idle)
    }

    @Test func cancellingLeavesTheEditorAsItWasWithNoFileAndNothingOnTheClipboard() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.startExport()
        #expect(model.isExporting)
        model.cancelExport()
        await model.export()

        #expect(model.exportState == .idle)
        #expect(model.message == RecordingExportError.cancelled.message)
        #expect(editor.pasteboard.files.isEmpty)
        #expect(try editor.exportedFiles().isEmpty)
        // The editor is usable again.
        model.trimStart(to: 1)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 1)])
    }

    @Test func whileExportingNothingCanBeEditedBecauseTheFileShowsTheEditsOfTheMomentItStarted() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        let before = model.edit
        model.startExport()
        model.trimStart(to: 2)
        model.selection = 1..<2
        model.cutSelection()
        model.setZoomScale(3, at: 0)
        model.addZoom(at: 2)
        model.removeZoom(at: 0)
        model.setClickEffect(false)
        model.exportLevel = .high
        model.undo()
        model.redo()
        #expect(model.edit == before && model.exportLevel == .chat)
        #expect(try editor.savedProject().cuts.isEmpty)
        model.startExport()
        await model.export()

        guard case .finished(let result) = model.exportState else { Issue.record("not finished"); return }
        #expect(abs(result.duration - model.duration) < 0.05)
        #expect(try editor.exportedFiles().count == 1)
    }

    @Test func theFinishedFileCanBeShownInFinder() async throws {
        let editor = try await EditorFixture()
        editor.model.revealExport()
        #expect(editor.revealed.isEmpty)
        await editor.model.export()
        editor.model.revealExport()
        guard case .finished(let result) = editor.model.exportState else { Issue.record("not finished"); return }
        #expect(editor.revealed == [result.url])
    }

    @Test func aRunningExportIsNotDismissedAndAFinishedOneIs() async throws {
        let editor = try await EditorFixture()
        editor.model.startExport()
        editor.model.dismissExport()
        #expect(editor.model.isExporting)
        await editor.model.export()
        editor.model.dismissExport()
        #expect(editor.model.exportState == .idle)
    }
}
