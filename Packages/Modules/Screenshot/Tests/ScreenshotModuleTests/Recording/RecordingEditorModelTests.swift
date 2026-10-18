import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// A player that plays nothing and makes no sound: it remembers what it was asked.
final class FakePreviewPlayer: PreviewPlaying {
    var editedTime = 0.0
    var isPlaying = false
    private(set) var loads: [(item: AVPlayerItem, time: Double)] = []
    private(set) var seeks: [Double] = []

    func load(_ item: AVPlayerItem, at editedTime: TimeInterval) {
        loads.append((item, editedTime))
        self.editedTime = editedTime
    }

    func seek(toEdited time: TimeInterval) {
        seeks.append(time)
        editedTime = time
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}

/// The recording the editor tests share: made once by the real writer, its files kept in memory, and written to a folder of its
/// own for each test, so that dozens of tests do not each start an encoder.
@MainActor enum EditorSample {
    struct Snapshot: Sendable {
        var files: [String: Data]
        var project: RecordingProject
        var activity: ActivityTrack
    }

    /// 7 s: 3 s, a pause, 4 s; a click at 1 s and one at 5.5 s, so two zooms are planned.
    static let clicks = [
        ActivityTrack.Click(t: 1, x: 40, y: 30, button: .left), ActivityTrack.Click(t: 5.5, x: 120, y: 60, button: .left),
    ]

    private static var task: Task<Snapshot, any Error>?

    static func snapshot() async throws -> Snapshot {
        if task == nil {
            task = Task {
                let recording = try await SampleRecording.make(
                    parts: [.init(seconds: 3, frameInterval: 0.1), .init(seconds: 4, frameInterval: 0.1)], clicks: clicks,
                    picture: { PixelBuffers.solid(width: 160, height: 90, grey: RecordingCompositionTests.level(of: Int($0 + 1e-6))) },
                    amplitude: { Float(RecordingCompositionTests.loudness(of: Int($0 + 1e-6))) }
                )
                var files: [String: Data] = [:]
                for segment in recording.project.segments { files[segment.fileName] = try Data(contentsOf: recording.folder.file(segment.fileName)) }
                return Snapshot(files: files, project: recording.project, activity: recording.activity)
            }
        }
        return try await task!.value
    }
}

/// An editor over the shared recording, with a fake player, a fake pasteboard and a folder of its own for exports.
@MainActor final class EditorFixture {
    let recording: SampleRecording
    let player = FakePreviewPlayer()
    let pasteboard = FakePasteboard()
    let exports: TestFolder
    private(set) var revealed: [URL] = []
    private(set) var model: RecordingEditorModel!

    static var clicks: [ActivityTrack.Click] { EditorSample.clicks }

    init(
        edit: (inout RecordingProject) -> Void = { _ in }, writeActivity: Bool = true, start: Bool = true,
        now: @escaping () -> Date = { .now }, save: ((RecordingProject) throws -> Void)? = nil
    ) async throws {
        let sample = try await EditorSample.snapshot()
        let folder = try TestFolder("editor")
        for (name, data) in sample.files { try data.write(to: folder.file(name)) }
        var project = sample.project
        edit(&project)
        try project.write(to: folder.url)
        if writeActivity { try sample.activity.write(to: folder.url) }
        recording = SampleRecording(folder: folder, project: project, activity: sample.activity)
        exports = try TestFolder("editor-exports")
        model = try RecordingEditorModel.load(
            folder: folder.url, player: player, pasteboard: pasteboard, exportDirectory: exports.url,
            reveal: { [unowned self] in revealed.append($0) }, now: now, save: save
        )
        try #require(model.zoomSegments.count == 2 || !writeActivity, "the fixture's clicks plan two zooms")
        if start { await model.start() }
    }

    var folder: URL { recording.folder.url }
    func savedProject() throws -> RecordingProject { try RecordingProject.load(from: folder) }
    func exportedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: exports.url.path(percentEncoded: false))
    }
}

@Suite struct RecordingEditorModelTests {
    // MARK: Opening

    @Test func opensARecordingFromItsFolderWithTheZoomsThatThePlannerFinds() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!

        #expect(abs(model.duration - 7) < 0.05)
        #expect(model.cutMap.editedDuration == model.duration)
        #expect(model.zoomSegments == ZoomPlanner.plan(activity: editor.recording.activity, rules: .standard, duration: model.duration))
        #expect(model.zoomSegments.count == 2)
        #expect(model.selectedZoom == nil && model.selection == nil && model.message == nil)
        #expect(!model.canUndo && !model.canRedo)
        #expect(model.clickEffect && model.exportLevel == .chat)
    }

    @Test func aRecordingStillBeingRecordedIsNotOpened() async throws {
        do {
            _ = try await EditorFixture(edit: { $0.status = .recording })
            Issue.record("the editor opened")
        } catch let error as RecordingEditorError {
            #expect(error == .stillRecording)
            #expect(error.message.contains("đang quay"))
        }
    }

    @Test func aFolderWithoutAProjectIsNotOpenedAndSaysWhy() throws {
        let folder = try TestFolder("editor-empty")
        do {
            _ = try RecordingEditorModel.load(
                folder: folder.url, player: FakePreviewPlayer(), pasteboard: FakePasteboard(), exportDirectory: folder.url
            )
            Issue.record("the editor opened")
        } catch {
            guard case .unreadable = error else { Issue.record("wrong error \(error)"); return }
            #expect(!error.message.isEmpty)
        }
    }

    @Test func aRecordingWhosePointerDataIsLostStillOpensWithoutAutomaticZooms() async throws {
        let editor = try await EditorFixture(writeActivity: false)
        #expect(editor.model.zoomSegments.isEmpty)
        #expect(editor.model.message?.contains("con trỏ") == true)
        editor.model.trimStart(to: 1)
        #expect(editor.model.cutMap.editedDuration < editor.model.duration)
    }

    // MARK: Cuts

    @Test func draggingTheStartHandleCutsTheBeginningAndDraggingItBackBringsItBack() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.trimStart(to: 1.5)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 1.5)])
        model.trimStart(to: 3)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 3)])
        model.trimStart(to: 0.5)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 0.5)])
        model.trimStart(to: 0)
        #expect(model.cutMap.cuts.isEmpty)
    }

    @Test func draggingTheEndHandleCutsTheEnd() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        let duration = model.duration
        model.trimEnd(to: 5)
        #expect(model.cutMap.cuts == [CutRange(start: 5, end: duration)])
        model.trimEnd(to: 6)
        #expect(model.cutMap.cuts == [CutRange(start: 6, end: duration)])
        model.trimEnd(to: duration)
        #expect(model.cutMap.cuts.isEmpty)
    }

    @Test func aPickedStretchIsCutAndEverythingAroundItStays() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selection = 2..<4
        #expect(model.canCutSelection && !model.selectionIsCut)
        model.cutSelection()
        #expect(model.cutMap.cuts == [CutRange(start: 2, end: 4)])
        #expect(model.selection == nil)
        #expect(abs(model.cutMap.editedDuration - (model.duration - 2)) < 1e-9)
    }

    @Test func cutsThatTouchOrOverlapBecomeOne() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selection = 1..<3
        model.cutSelection()
        model.selection = 2.5..<5
        model.cutSelection()
        model.trimStart(to: 1.5)
        // The trim reaches into the first cut: they are one stretch now.
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 5)])
    }

    @Test func aCutStretchComesBackWhenItIsRestored() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selection = 1..<2
        model.cutSelection()
        model.selection = 4..<5
        model.cutSelection()
        model.selection = 4.2..<4.6
        #expect(model.selectionIsCut)
        model.restoreSelection()
        #expect(model.cutMap.cuts == [CutRange(start: 1, end: 2)])
        #expect(model.selection == nil)
        // A selection that is not inside a cut restores nothing.
        model.selection = 0..<1.5
        #expect(!model.selectionIsCut)
        model.restoreSelection()
        #expect(model.cutMap.cuts == [CutRange(start: 1, end: 2)])
    }

    @Test func nothingShorterThanAFlickerIsCutAndNotEverythingMayBeCut() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selection = 2..<2.01
        #expect(!model.canCutSelection)
        model.cutSelection()
        #expect(model.cutMap.cuts.isEmpty)

        // Picking all of it and cutting leaves nothing, so it is refused, and the pick stays for the person to change.
        model.selection = 0..<model.duration
        model.cutSelection()
        #expect(model.cutMap.cuts.isEmpty && !model.canUndo)
        #expect(model.message?.contains("cắt hết") == true)
        #expect(model.selection == 0..<model.duration)
    }

    @Test func aHandleDraggedOntoTheOtherOneStopsWhereTheShortestVideoWouldBe() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        let duration = model.duration
        model.trimStart(to: duration)
        #expect(abs(model.cutMap.editedDuration - RecordingEditorModel.minimumKept) < 1e-9)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: duration - RecordingEditorModel.minimumKept)])

        model.trimStart(to: 0)
        model.trimEnd(to: 3)
        model.trimStart(to: 6)
        let cuts = model.cutMap.cuts
        #expect(cuts.count == 2 && abs(cuts[0].end - 2.8) < 1e-9 && cuts[1] == CutRange(start: 3, end: duration))
        // And the other handle cannot be pushed onto it either.
        model.trimEnd(to: -1)
        #expect(model.cutMap.cuts.count == 2 && abs(model.cutMap.cuts[1].start - 3) < 1e-9)
        #expect(abs(model.cutMap.editedDuration - RecordingEditorModel.minimumKept) < 1e-9)
        #expect(model.message == nil)
    }

    @Test func playingASecondInsideACutLandsAtTheStartOfWhatFollows() async throws {
        let editor = try await EditorFixture(edit: { $0.cuts = [CutRange(start: 2, end: 4)] })
        let model = editor.model!
        model.seek(toRecording: 1)
        #expect(editor.player.seeks.last == 1)
        model.seek(toRecording: 3)
        #expect(editor.player.seeks.last == 2)
        model.seek(toRecording: 5)
        #expect(editor.player.seeks.last == 3)
        // Past the end, or before the start.
        model.seek(toRecording: 100)
        #expect(editor.player.seeks.last == model.cutMap.editedDuration)
        model.seek(toRecording: -3)
        #expect(editor.player.seeks.last == 0)
    }

    @Test func thePlayheadIsTheRecordingMomentOfTheEditedTimeThePlayerIsAt() async throws {
        let editor = try await EditorFixture(edit: { $0.cuts = [CutRange(start: 2, end: 4)] })
        editor.player.editedTime = 1.5
        #expect(editor.model.playhead == 1.5)
        editor.player.editedTime = 2.5
        #expect(editor.model.playhead == 4.5)
        editor.player.editedTime = 99
        #expect(editor.model.playhead == editor.model.duration)
    }

    // MARK: Zooms

    @Test func theFirstZoomEditWritesThePlannedListAndUndoGivesBackTheNeverEditedState() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        let planned = model.zoomSegments
        #expect(try editor.savedProject().zoomSegments == nil)

        model.setZoomScale(3, at: 0)
        #expect(model.zoomSegments.count == 2 && model.zoomSegments[0].scale == 3 && model.zoomSegments[1] == planned[1])
        #expect(try editor.savedProject().zoomSegments?.count == 2)

        model.undo()
        // Not an empty list and not a copy of the plan: the person has not edited the zooms.
        #expect(try editor.savedProject().zoomSegments == nil)
        #expect(model.zoomSegments == planned)
        model.redo()
        #expect(model.zoomSegments[0].scale == 3)
    }

    @Test func theScaleStaysBetweenOneQuarterAndThreeTimes() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.setZoomScale(10, at: 0)
        #expect(model.zoomSegments[0].scale == 3)
        model.setZoomScale(1, at: 0)
        #expect(model.zoomSegments[0].scale == 1.25)
        model.setZoomScale(1.8, at: 1)
        #expect(model.zoomSegments[1].scale == 1.8)
        model.setZoomScale(2, at: 7)
        #expect(model.zoomSegments.count == 2)
    }

    @Test func dragTheEdgesToChangeWhenAZoomStartsAndEnds() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        let first = model.zoomSegments[0]
        model.setZoomStart(0.25, at: 0)
        model.setZoomEnd(3.4, at: 0)
        #expect(model.zoomSegments[0].start == 0.25 && model.zoomSegments[0].end == 3.4)
        #expect(model.zoomSegments[0].focus == first.focus)
        #expect(model.zoomSegments[0].scale == first.scale)
        // The picture stays in for at least half a second, and inside the recording.
        model.setZoomStart(9, at: 0)
        #expect(model.zoomSegments[0].start == 3.4 - RecordingEditorModel.minimumZoom)
        model.setZoomEnd(-4, at: 0)
        #expect(model.zoomSegments[0].end == model.zoomSegments[0].start + RecordingEditorModel.minimumZoom)
        model.setZoomStart(-4, at: 0)
        #expect(model.zoomSegments[0].start == 0)
        model.setZoomEnd(500, at: 1)
        #expect(model.zoomSegments[1].end == model.duration)
    }

    @Test func aZoomIsRemovedAndTheSelectionFollows() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selectZoom(1)
        #expect(model.selectedZoom == 1)
        model.removeSelectedZoom()
        #expect(model.zoomSegments.count == 1 && model.selectedZoom == nil)
        model.removeZoom(at: 0)
        // Every zoom removed is an empty list, which is not "never edited".
        #expect(model.zoomSegments.isEmpty)
        #expect(try editor.savedProject().zoomSegments == [])
        model.undo()
        model.undo()
        #expect(model.zoomSegments.count == 2)
        #expect(try editor.savedProject().zoomSegments == nil)
    }

    @Test func aSelectedZoomThatNoLongerExistsAfterUndoIsDeselected() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.addZoom(at: 5.5)
        #expect(model.zoomSegments.count == 3)
        #expect(model.selectedZoom == 2)
        model.undo()
        #expect(model.selectedZoom == nil)
        model.selectZoom(9)
        #expect(model.selectedZoom == nil)
        model.selectZoom(-1)
        #expect(model.selectedZoom == nil)
    }

    @Test func addingAZoomHereLooksWhereThePointerWasAndSelectsIt() async throws {
        let activity = ActivityTrack(
            pixelWidth: 160, pixelHeight: 90, keyboardRecorded: true, pointer: [.init(t: 5, x: 100, y: 20), .init(t: 5.5, x: 110, y: 25)],
            clicks: EditorFixture.clicks
        )
        let editor = try await EditorFixture(start: false)
        // Same recording, with that pointer path.
        try activity.write(to: editor.folder)
        let model = try RecordingEditorModel.load(
            folder: editor.folder, player: editor.player, pasteboard: editor.pasteboard, exportDirectory: editor.exports.url
        )
        model.addZoom(at: 5)
        let index = try #require(model.zoomSegments.firstIndex { $0.manual })
        let added = model.zoomSegments[index]
        // Three seconds, but the recording ends first.
        #expect(added.manual && added.start == 5 && added.end == model.duration && added.scale == ZoomRules.standard.scale)
        #expect(added.focus.first.map { $0.t == 5 && $0.x == 100 && $0.y == 20 } == true)
        #expect(model.selectedZoom == index)
        #expect(try editor.savedProject().zoomSegments?[index].manual == true)
    }

    @Test func aZoomAddedNearTheEndStillFitsInTheRecording() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.addZoom(at: model.duration - 0.1)
        let added = try #require(model.zoomSegments.first { $0.manual })
        #expect(added.end <= model.duration && added.end - added.start >= RecordingEditorModel.minimumZoom)
        model.addZoom(at: -5)
        #expect(model.zoomSegments.contains { $0.manual && $0.start == 0 })
    }

    @Test func zoomsStayInTheOrderTheyStartIn() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.addZoom(at: 3)
        model.addZoom(at: 0.2)
        #expect(model.zoomSegments.map(\.start) == model.zoomSegments.map(\.start).sorted())
        #expect(model.zoomSegments.count == 4)
    }

    @Test func anEditThatChangesNothingIsNotAStepAndWritesNothing() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.setZoomScale(model.zoomSegments[0].scale, at: 0)
        model.setZoomStart(model.zoomSegments[0].start, at: 0)
        model.trimStart(to: 0)
        model.trimEnd(to: model.duration)
        model.setClickEffect(true)
        #expect(!model.canUndo)
        #expect(try editor.savedProject().zoomSegments == nil)
    }

    // MARK: Click effect and level

    @Test func theClickRingsCanBeTurnedOffAndUndone() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.setClickEffect(false)
        #expect(!model.clickEffect)
        #expect(try editor.savedProject().clickEffect == false)
        model.undo()
        #expect(model.clickEffect)
        #expect(try editor.savedProject().clickEffect)
    }

    @Test func theExportLevelIsKeptButIsNotAStepToUndo() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.exportLevel = .high
        #expect(try editor.savedProject().exportLevel == .high)
        #expect(!model.canUndo)
        model.setClickEffect(false)
        model.undo()
        #expect(model.exportLevel == .high)
        #expect(try editor.savedProject().exportLevel == .high)
    }

    // MARK: Saving

    @Test func everyEditIsInProjectJsonAndAnotherEditorOpensWithIt() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.selection = 2..<3
        model.cutSelection()
        model.setZoomScale(2.5, at: 1)
        model.addZoom(at: 6)
        model.setClickEffect(false)
        model.exportLevel = .high

        let reopened = try RecordingEditorModel.load(
            folder: editor.folder, player: FakePreviewPlayer(), pasteboard: FakePasteboard(), exportDirectory: editor.exports.url
        )
        #expect(reopened.cutMap.cuts == [CutRange(start: 2, end: 3)])
        #expect(reopened.zoomSegments == model.zoomSegments)
        #expect(!reopened.clickEffect && reopened.exportLevel == .high)
        // What the recording is stays as it was.
        let saved = try editor.savedProject()
        #expect(saved.segments == editor.recording.project.segments && saved.id == editor.recording.project.id)
        #expect(saved.region == editor.recording.project.region && saved.status == .finished)
    }

    @Test func undoAndRedoAreWrittenToo() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        model.trimStart(to: 1)
        model.undo()
        #expect(try editor.savedProject().cuts.isEmpty)
        #expect(!model.canUndo && model.canRedo)
        model.redo()
        #expect(try editor.savedProject().cuts == [CutRange(start: 0, end: 1)])
    }

    @Test func aSaveThatFailsTellsTheUserAndTheEditStays() async throws {
        struct Refused: Error {}
        let editor = try await EditorFixture(save: { _ in throw Refused() })
        let model = editor.model!
        model.trimStart(to: 1)
        #expect(model.cutMap.cuts == [CutRange(start: 0, end: 1)])
        #expect(model.message?.contains("Không lưu được") == true)
        model.dismissMessage()
        #expect(model.message == nil)
    }

    // MARK: Preview

    @Test func thePreviewIsTheEditedVideoAndIsShownFromTheStart() async throws {
        let editor = try await EditorFixture(edit: { $0.cuts = [CutRange(start: 1, end: 3)] })
        let preview = try #require(editor.model.preview)
        #expect(abs(preview.duration - 5) < 0.05)
        #expect(editor.model.previewError == nil)
        #expect(editor.player.loads.count == 1 && editor.player.loads[0].time == 0)
        #expect(editor.player.loads[0].item.videoComposition != nil)
    }

    @Test func theBigPreviewOfALargeRecordingIsDrawnAtNoMoreThan1080p() async throws {
        let recording = try await BigSample.make(width: 2560, height: 1440, seconds: 0.5, frameInterval: 0.25)
        try recording.project.write(to: recording.folder.url)
        try recording.activity.write(to: recording.folder.url)
        let model = try RecordingEditorModel.load(
            folder: recording.folder.url, player: FakePreviewPlayer(), pasteboard: FakePasteboard(), exportDirectory: recording.folder.url
        )
        await model.start()

        let preview = try #require(model.preview)
        #expect(preview.renderSize == CGSize(width: 1920, height: 1080))
        #expect(preview.videoComposition.renderSize == CGSize(width: 1920, height: 1080))
        // The picture it is made from is still the full one: the camera's size is the recording's.
        #expect(preview.camera.frameSize == CGSize(width: 2560, height: 1440))
        #expect(RecordingEditorModel.previewSize(of: model.project) == CGSize(width: 1920, height: 1080))
    }

    @Test func anEditShowsANewPreviewAtTheSameMomentOfTheRecording() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        editor.player.editedTime = 5
        model.selection = 1..<3
        model.cutSelection()
        await model.settle()

        // 5 s of the recording is 3 s of the video once 2 s before it are cut.
        #expect(editor.player.loads.count == 2)
        #expect(abs(editor.player.loads[1].time - 3) < 1e-9)
        #expect(abs((model.preview?.duration ?? 0) - 5) < 0.05)

        model.undo()
        await model.settle()
        #expect(editor.player.loads.count == 3)
        #expect(abs(editor.player.loads[2].time - 5) < 1e-9)
        #expect(abs((model.preview?.duration ?? 0) - 7) < 0.05)
    }

    @Test func aMomentThatWasCutMovesToWhatFollowsInTheNewPreview() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        editor.player.editedTime = 2
        model.selection = 1..<3
        model.cutSelection()
        await model.settle()
        #expect(abs(editor.player.loads[1].time - 1) < 1e-9)
    }

    @Test func manyQuickEditsEndWithThePreviewOfTheLastOne() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        for end in [1.0, 2.0, 3.0, 4.0] { model.trimStart(to: end) }
        model.trimEnd(to: 6)
        await model.settle()

        let preview = try #require(model.preview)
        #expect(abs(preview.duration - 2) < 0.05)
        // Each rebuild that was overtaken is dropped: the player was given the first preview and the newest, and no other.
        #expect(editor.player.loads.count == 2)
        let held = try #require(editor.player.loads.last?.item.asset)
        #expect(abs(try await held.load(.duration).seconds - 2) < 0.05)
        #expect(model.previewRevision == editor.player.loads.count)
    }

    @Test func aRecordingWhoseFileIsGoneSaysSoInsteadOfShowingNothing() async throws {
        let editor = try await EditorFixture(start: false)
        try FileManager.default.removeItem(at: editor.folder.appending(path: "segment-001.mov"))
        await editor.model.start()
        #expect(editor.model.preview == nil)
        #expect(editor.model.previewError == RecordingCompositionError.missingFile("segment-001.mov").message)
    }

    @Test func playAndPauseGoToThePlayerAndPlayStartsOverAtTheEnd() async throws {
        let editor = try await EditorFixture()
        let model = editor.model!
        #expect(!model.isPlaying)
        model.togglePlayback()
        #expect(editor.player.isPlaying && model.isPlaying)
        model.togglePlayback()
        #expect(!editor.player.isPlaying)
    }

    // MARK: Thumbnails

    @Test func thePictureStripShowsTheWholeRecordingAndKeepsShowingItWhenPartsAreCut() async throws {
        let editor = try await EditorFixture(edit: { $0.cuts = [CutRange(start: 1, end: 3)] })
        let model = editor.model!
        #expect(model.thumbnails.count == RecordingEditorModel.thumbnailCount)
        let images = model.thumbnails.compactMap { $0 }
        #expect(images.count == RecordingEditorModel.thumbnailCount)
        // Thumbnail `i` is a picture from its own place in the recording, cut or not: the greys climb a step every second, and it
        // may be the picture of a neighbouring second (the generator takes the nearest picture it can decode cheaply).
        var greys: [Int] = []
        for (index, image) in model.thumbnails.enumerated() {
            let second = Int((Double(index) + 0.5) / Double(RecordingEditorModel.thumbnailCount) * model.duration)
            let grey = try #require(image.map { Self.centreGrey(of: $0) })
            greys.append(grey)
            let near = (max(second - 1, 0)...min(second + 1, 6)).map { Int(RecordingCompositionTests.level(of: $0)) }
            #expect(near.contains { abs(grey - $0) <= 14 }, "thumbnail \(index): \(grey), second \(second)")
        }
        #expect(greys == greys.sorted())
        #expect(try #require(greys.last) - (greys.first ?? 0) >= 100)
        model.selection = 5..<6
        model.cutSelection()
        await model.settle()
        #expect(model.thumbnails.count == RecordingEditorModel.thumbnailCount)
    }

    static func centreGrey(of image: CGImage) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return Int(pixel[1])
    }
}
