import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// Recording from the notch, through the registry with a recorder that records nothing.
@Suite(.timeLimit(.minutes(1))) final class ScreenshotModuleRecordingTests {
    let fakes = FakeRecordingSystem()
    let rig: ModuleRig
    var module: ScreenshotModule { rig.module }
    var recorder: FakeRecorder { fakes.recorder }
    var editors: FakeRecordingEditors { fakes.editors }
    var harness: RegistryHarness { rig.harness }

    init() throws { rig = try ModuleRig(recording: fakes.dependencies) }

    /// Starts a recording of what the overlay answers, with no countdown, and waits until it runs.
    func record(_ target: RecordingTarget = .region) async throws {
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        module.beginRecording(target)
        await rig.waitUntil { rig.phase == .recording }
        #expect(rig.phase == .recording)
    }

    /// Starts with the countdown and waits until it counts.
    func beginCounting(_ target: RecordingTarget = .region) async {
        module.beginRecording(target)
        await rig.waitUntil { rig.phase == .countdown(3) }
    }

    // MARK: Starting

    @Test func eachWayOfPickingAsksTheOverlayForItsOwnMode() async throws {
        await rig.start()
        rig.overlay.result = nil
        for (target, mode) in [(RecordingTarget.region, SelectionMode.recordRegion), (.window, .recordWindow), (.any, .recordRegionOrWindow)] {
            module.beginRecording(target)
            await rig.waitUntil { rig.overlay.runs.last?.mode == mode && rig.phase == .idle }
        }

        #expect(rig.overlay.runs.map(\.mode) == [.recordRegion, .recordWindow, .recordRegionOrWindow])
        // Esc in the overlay starts nothing.
        #expect(recorder.starts.isEmpty && rig.phase == .idle && rig.activity == nil)
        #expect(!module.isSelecting)
    }

    @Test func aWholeScreenNeedsNoOverlayAndIsTheDisplayUnderThePointer() async throws {
        let second = DisplayInfo(id: 2, frame: CGRect(x: 100, y: 0, width: 200, height: 100), scale: 1)
        rig.service.frozen.append(FrozenDisplay(info: second, image: rig.service.frozen[0].image))
        fakes.pointer = CGPoint(x: 150, y: 50)
        await rig.start()

        try await record(.screen)

        #expect(rig.overlay.runs.isEmpty && rig.service.freezeCount == 0)
        #expect(rig.service.displayRequests == 1)
        #expect(recorder.starts.first?.region == RecordingRegion(fullScreen: second))
    }

    @Test func aWholeScreenWithThePointerOnNoDisplayIsTheFirst() async throws {
        fakes.pointer = CGPoint(x: -500, y: -500)
        await rig.start()

        try await record(.screen)

        #expect(recorder.starts.first?.region == RecordingRegion(fullScreen: ModuleRig.display))
    }

    @Test func theCountdownHoldsTheStartForThreeSecondsOnTheSchedulerAndShowsInTheNotch() async throws {
        await rig.start()
        await beginCounting()

        #expect(recorder.starts.isEmpty && rig.phase == .countdown(3))
        #expect(rig.activity?.id == "recording" && rig.activity?.summary == "Quay màn hình sau 3 giây" && rig.activity?.hasBottom == true)
        // The overlay is gone and the notch closed before it counts.
        #expect(rig.harness.presenter.closeCount >= 1)

        harness.scheduler.advance(by: .seconds(1))
        #expect(rig.phase == .countdown(2) && rig.activity?.summary == "Quay màn hình sau 2 giây")
        harness.scheduler.advance(by: .seconds(1))
        #expect(rig.phase == .countdown(1) && recorder.starts.isEmpty)
        harness.scheduler.advance(by: .seconds(1))
        await rig.waitUntil { rig.phase == .recording }

        #expect(recorder.starts.count == 1)
        #expect(rig.activity?.summary == "Đang quay màn hình")
    }

    @Test func theRecordingGetsExactlyThePixelsTheOverlayPicked() async throws {
        await rig.start()
        try await record()

        let start = try #require(recorder.starts.first)
        #expect(start.region.display == ModuleRig.display)
        #expect(start.region.pixelRect == CGRect(x: 20, y: 30, width: 40, height: 50))
    }

    @Test func withTheCountdownOffTheRecordingStartsAtOnce() async throws {
        await rig.start()
        try await record()

        #expect(recorder.starts.count == 1)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func cancellingTheCountdownStartsNothingAndTakesTheActivityAway() async throws {
        await rig.start()
        await beginCounting()

        module.cancelRecordingCountdown()
        harness.scheduler.advance(by: .seconds(10))

        #expect(rig.phase == .idle && rig.activity == nil && recorder.starts.isEmpty)
        #expect(harness.registry.menuItems.isEmpty)
    }

    @Test func theShortcutPressedDuringTheCountdownCancelsIt() async throws {
        await rig.start()
        await beginCounting()

        #expect(harness.hotkeyBackend.trigger("screenshot_record"))

        #expect(rig.phase == .idle && rig.activity == nil)
        harness.scheduler.advance(by: .seconds(10))
        #expect(recorder.starts.isEmpty)
    }

    @Test func theRecordingIsAskedForWhatTheSettingsSay() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        fakes.microphones = [MicrophoneDevice(id: "USB-1", name: "USB")]
        settings.set("USB-1", for: keys.recordMicrophone)
        settings.set(true, for: keys.recordSystemAudio)
        try await record()
        #expect(recorder.starts.last?.options == RecordingOptions(microphone: .device("USB-1"), systemAudio: true, fps: 60))
        try await finish()

        // A microphone that was unplugged is the system's default, never a failure.
        fakes.microphones = []
        settings.set(false, for: keys.recordSystemAudio)
        try await record()
        #expect(recorder.starts.last?.options == RecordingOptions(microphone: .systemDefault, systemAudio: false, fps: 60))
        try await finish()

        settings.set(MicrophoneChoice.off, for: keys.recordMicrophone)
        try await record()
        #expect(recorder.starts.last?.options == RecordingOptions(microphone: nil, systemAudio: false, fps: 60))
    }

    @Test func missingScreenAccessSaysSoAndOpensNoOverlay() async throws {
        await rig.start()
        rig.system.hasScreenAccess = false

        module.beginRecording(.region)
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(harness.presenter.toastCount == 1)
        #expect(rig.service.freezeCount == 0 && rig.overlay.runs.isEmpty && recorder.starts.isEmpty)
        #expect(rig.phase == .idle)
        // Settings are opened by nobody: the person is told how.
        #expect(harness.permissions.openedSettings.isEmpty)
    }

    @Test func aMicrophoneNeverAskedAboutIsAskedBeforeTheOverlayAndTheCountdown() async throws {
        await rig.start()
        harness.permissions.statuses[.microphone] = .notDetermined
        var seen: [(overlayRuns: Int, phase: RecordingPhase)] = []
        harness.permissions.awaitAnswer = { [rig] in seen.append((rig.overlay.runs.count, rig.phase)) }

        await beginCounting()

        #expect(harness.permissions.requested == [.microphone])
        #expect(seen.count == 1 && seen[0].overlayRuns == 0 && seen[0].phase == .selecting)
        #expect(rig.overlay.runs.count == 1 && rig.phase == .countdown(3))
    }

    @Test func aCaptureIsIgnoredWhileARecordingWaitsForAnAnswerAboutTheMicrophone() async throws {
        await rig.start()
        harness.permissions.statuses[.microphone] = .notDetermined
        harness.permissions.awaitAnswer = { [module, rig] in
            await module.capture(mode: .regionOrWindow)
            #expect(rig.service.freezeCount == 0 && rig.overlay.runs.isEmpty)
        }

        await beginCounting()

        #expect(rig.service.freezeCount == 1 && rig.overlay.runs.map(\.mode) == [.recordRegion])
    }

    @Test func aRefusedMicrophoneStartsNothingAndSaysHowToChangeIt() async throws {
        await rig.start()
        harness.permissions.statuses[.microphone] = .notDetermined
        harness.permissions.requestResult = .denied

        module.beginRecording(.region)
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(harness.presenter.toastCount == 1 && rig.overlay.runs.isEmpty && recorder.starts.isEmpty && rig.phase == .idle)
        #expect(harness.permissions.openedSettings.isEmpty)
        // Asked once: a refusal is not asked again.
        module.beginRecording(.region)
        await rig.waitUntil { harness.presenter.toastCount == 2 }
        #expect(harness.presenter.toastCount == 2 && harness.permissions.requested == [.microphone])
    }

    @Test func withTheMicrophoneOffNoMicrophonePermissionIsNeeded() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        settings.set(MicrophoneChoice.off, for: keys.recordMicrophone)
        harness.permissions.statuses[.microphone] = .denied

        try await record()

        #expect(recorder.starts.count == 1 && recorder.starts[0].options.microphone == nil)
    }

    @Test func aSecondStartIsIgnoredWhileOneIsGoingOn() async throws {
        await rig.start()
        try await record()

        module.beginRecording(.region)
        #expect(harness.hotkeyBackend.trigger("screenshot_recordPause"))
        await rig.waitUntil { recorder.pauseCount == 1 }
        module.beginRecording(.region)
        try await Task.sleep(for: .milliseconds(30))

        #expect(recorder.starts.count == 1 && rig.overlay.runs.count == 1)
    }

    @Test func aRecorderThatCannotStartLeavesNothingRunning() async throws {
        await rig.start()
        recorder.startError = .encoderUnavailable("x")
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)

        module.beginRecording(.region)
        await rig.waitUntil { harness.presenter.toastCount == 1 && rig.phase == .idle }

        #expect(rig.phase == .idle && rig.activity == nil && harness.presenter.toastCount == 1)
        #expect(harness.registry.menuItems.isEmpty && editors.opened.isEmpty)
    }

    @Test func aSecondStartWhileTheStreamIsStartingIsIgnored() async throws {
        await rig.start()
        recorder.isStartGated = true
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)

        module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .starting }
        module.beginRecording(.region)
        harness.hotkeyBackend.trigger("screenshot_record")
        try await Task.sleep(for: .milliseconds(30))
        #expect(rig.overlay.runs.count == 1 && recorder.starts.count == 1)

        recorder.releaseStart()
        await rig.waitUntil { rig.phase == .recording }
        #expect(rig.phase == .recording)
    }

    // MARK: While recording

    @Test func theNotchShowsTheRecordingWithItsButtonsAndNoTickPublishesIt() async throws {
        await rig.start()
        try await record()

        let activity = try #require(rig.activity)
        #expect(activity.id == "recording" && activity.summary == "Đang quay màn hình")
        #expect(activity.priority == .high && activity.hasBottom && activity.minimal != nil)
        // The clock is the system's: the activity is published at the start, a pause, a resume and the end, and never on a second.
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func pausingAndResumingFollowTheRecorderAndTheNotch() async throws {
        await rig.start()
        try await record()

        module.toggleRecordingPause()
        await rig.waitUntil { rig.phase == .paused }
        #expect(recorder.pauseCount == 1 && rig.activity?.summary == "Đã tạm dừng quay")
        #expect(harness.registry.menuItems.map(\.title).last == "Tiếp tục quay")

        module.toggleRecordingPause()
        await rig.waitUntil { rig.phase == .recording }
        #expect(recorder.resumeCount == 1 && rig.activity?.summary == "Đang quay màn hình")
        #expect(harness.registry.menuItems.map(\.title).last == "Tạm dừng quay")
    }

    @Test func aResumeThatFailsLeavesTheRecordingPausedAndSaysSo() async throws {
        await rig.start()
        try await record()
        module.toggleRecordingPause()
        await rig.waitUntil { rig.phase == .paused }
        recorder.resumeError = .failed("x")

        module.toggleRecordingPause()
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(rig.phase == .paused && harness.presenter.toastCount == 1)
    }

    @Test func stoppingOpensTheEditorOnTheNewRecordingAndTakesTheNotchBack() async throws {
        await rig.start()
        try await record()
        let id = try #require(recorder.currentRecordingID)

        module.stopRecording()
        await rig.waitUntil { !editors.opened.isEmpty }

        #expect(editors.opened == [rig.recordingStore.folder(for: id)])
        #expect(rig.phase == .idle && rig.activity == nil && recorder.stopCount == 1)
        #expect(harness.registry.menuItems.isEmpty)
        // And the list has it.
        await rig.waitUntil { module.state.recordings.map(\.id) == [id] }
        #expect(module.state.recordings.map(\.id) == [id])
    }

    @Test func theNewRecordingStartsWithThePersonsDefaults() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        settings.set(ExportLevel.high, for: keys.exportLevel)
        settings.set(2.5, for: keys.zoomScale)
        settings.set(3.0, for: keys.zoomHoldSeconds)
        settings.set(false, for: keys.clickEffect)
        try await record()
        let id = try #require(recorder.currentRecordingID)

        module.stopRecording()
        await rig.waitUntil { !editors.opened.isEmpty }

        let project = try RecordingProject.load(from: rig.recordingStore.folder(for: id))
        #expect(project.exportLevel == .high && project.zoomRules.scale == 2.5 && project.zoomRules.idleTimeout == 3.0 && !project.clickEffect)
        // The rest of the rules are the standard ones, and the recording itself is untouched.
        #expect(project.zoomRules.zoomInDuration == ZoomRules.standard.zoomInDuration && project.status == .finished && project.segments.count == 1)
    }

    @Test func theDefaultsAreTheStandardOnesUntilTheyAreChanged() async throws {
        await rig.start()
        try await record()
        let id = try #require(recorder.currentRecordingID)

        module.stopRecording()
        await rig.waitUntil { !editors.opened.isEmpty }

        let project = try RecordingProject.load(from: rig.recordingStore.folder(for: id))
        #expect(project.exportLevel == .chat && project.zoomRules == .standard && project.clickEffect)
    }

    @Test func reopeningFromTheListKeepsWhatWasChosenForThatRecording() async throws {
        await rig.start()
        let existing = try rig.makeRecording()
        var chosen = try RecordingProject.load(from: rig.recordingStore.folder(for: existing.id))
        chosen.exportLevel = .high
        chosen.clickEffect = false
        try chosen.write(to: rig.recordingStore.folder(for: existing.id))
        await module.refreshRecordings()

        module.openRecording(try #require(module.state.recordings.first))

        #expect(editors.opened == [rig.recordingStore.folder(for: existing.id)])
        #expect(try RecordingProject.load(from: rig.recordingStore.folder(for: existing.id)) == chosen)
    }

    @Test func theRecordingBeingMadeCannotBeOpened() async throws {
        await rig.start()
        try await record()
        let live = FakeRecorder.project(id: try #require(recorder.currentRecordingID), region: nil, status: .recording, seconds: 1)
        let toasts = harness.presenter.toastCount

        module.recording?.open(live.id)

        #expect(editors.opened.isEmpty && harness.presenter.toastCount == toasts + 1)
    }

    @Test func anEditorThatRefusesIsReportedNotIgnored() async throws {
        await rig.start()
        editors.openError = .unreadable("x")
        try await record()

        module.stopRecording()
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(harness.presenter.toastCount == 1 && editors.opened.isEmpty && rig.phase == .idle)
    }

    @Test func aRecordingThatCannotBeClosedIsReportedAndLeavesTheNotchFree() async throws {
        await rig.start()
        try await record()
        recorder.stopError = .nothingRecorded

        module.stopRecording()
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(rig.phase == .idle && rig.activity == nil && editors.opened.isEmpty && harness.presenter.toastCount == 1)
    }

    @Test func aRecordingTheSystemStoppedIsKeptAndOpened() async throws {
        await rig.start()
        try await record()
        let id = try #require(recorder.currentRecordingID)

        recorder.end(.finished)
        await rig.waitUntil { !editors.opened.isEmpty }

        #expect(editors.opened == [rig.recordingStore.folder(for: id)])
        #expect(rig.phase == .idle && rig.activity == nil)
        #expect(harness.registry.menuItems.isEmpty)
    }

    @Test func aRecordingCutShortIsOpenedToo() async throws {
        await rig.start()
        try await record()

        recorder.end(.interrupted)
        await rig.waitUntil { !editors.opened.isEmpty }

        #expect(editors.opened.count == 1 && rig.phase == .idle)
    }

    @Test func aRecordingThatFailedWithNothingToKeepOnlySaysSo() async throws {
        await rig.start()
        try await record()

        recorder.end(nil, error: .writerFailed("disk"))
        await rig.waitUntil { harness.presenter.toastCount == 1 }

        #expect(editors.opened.isEmpty && rig.phase == .idle && rig.activity == nil && harness.presenter.toastCount == 1)
    }

    // MARK: Menu and shortcuts

    @Test func theStatusMenuOffersStopAndPauseOnlyWhileRecording() async throws {
        await rig.start()
        #expect(harness.registry.menuItems.isEmpty)
        try await record()
        recorder.elapsed = 83

        let items = harness.registry.menuItems
        #expect(items.map(\.id) == ["stopRecording", "pauseRecording"])
        #expect(items[0].title == "🔴 Dừng quay (01:23)" && items[1].title == "Tạm dừng quay")

        await harness.registry.setEnabled(false, for: "screenshot")
        #expect(harness.registry.menuItems.isEmpty)
    }

    @Test func theStatusMenuOffersToCancelDuringTheCountdown() async throws {
        await rig.start()
        await beginCounting()

        let items = harness.registry.menuItems
        #expect(items.map(\.id) == ["cancelRecording"] && items[0].title == "Huỷ quay (còn 3 giây)")
        items[0].action()
        #expect(rig.phase == .idle && harness.registry.menuItems.isEmpty)
    }

    @Test func theMenuEntriesStopAndPause() async throws {
        await rig.start()
        try await record()

        harness.registry.menuItems[1].action()
        await rig.waitUntil { rig.phase == .paused }
        #expect(recorder.pauseCount == 1)

        harness.registry.menuItems[0].action()
        await rig.waitUntil { !editors.opened.isEmpty }
        #expect(recorder.stopCount == 1 && rig.phase == .idle && harness.registry.menuItems.isEmpty)
    }

    @Test func theRecordShortcutStartsWithTheOverlayAndStopsWhatRuns() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)

        #expect(harness.hotkeyBackend.trigger("screenshot_record"))
        await rig.waitUntil { rig.phase == .recording }
        #expect(rig.overlay.runs.map(\.mode) == [.recordRegionOrWindow])

        #expect(harness.hotkeyBackend.trigger("screenshot_record"))
        await rig.waitUntil { !editors.opened.isEmpty }
        #expect(recorder.stopCount == 1 && rig.phase == .idle)
    }

    @Test func thePauseShortcutPausesAndResumesAndDoesNothingWhenIdle() async throws {
        await rig.start()
        #expect(harness.hotkeyBackend.trigger("screenshot_recordPause"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(recorder.pauseCount == 0)

        try await record()
        #expect(harness.hotkeyBackend.trigger("screenshot_recordPause"))
        await rig.waitUntil { rig.phase == .paused }
        #expect(harness.hotkeyBackend.trigger("screenshot_recordPause"))
        await rig.waitUntil { rig.phase == .recording }
        #expect(recorder.pauseCount == 1 && recorder.resumeCount == 1)
    }

    // MARK: The list

    @Test func startListsTheRecordingsOnDiskNewestFirst() async throws {
        let older = try rig.makeRecording(createdAt: Date(timeIntervalSince1970: 1_700_000_000), bytes: 2_000)
        let newer = try rig.makeRecording(createdAt: Date(timeIntervalSince1970: 1_800_000_000), bytes: 1_000)

        await rig.start()
        await rig.waitUntil { module.state.recordings.count == 2 }

        #expect(module.state.recordings.map(\.id) == [newer.id, older.id])
        #expect(module.state.recordings.map(\.bytes).allSatisfy { $0 > 1_000 })
    }

    @Test func theListNeverRescuesTheRecordingBeingMade() async throws {
        await rig.start()
        try await record()
        let id = try #require(recorder.currentRecordingID)
        let file = rig.recordingStore.folder(for: id).appending(path: "project.json")
        let before = try Data(contentsOf: file)

        await module.refreshRecordings()

        // A recording marked as being recorded that the session does not name is one a crash left, and is rescued: this one is named.
        #expect(try Data(contentsOf: file) == before)
        #expect(try RecordingProject.load(from: rig.recordingStore.folder(for: id)).status == .recording)
        #expect(module.state.recordings.map(\.id) == [id] && module.state.recordings.first?.isIncomplete == false)
    }

    @Test func deletingRemovesThatRecordingsFolderAndNothingElse() async throws {
        await rig.start()
        let doomed = try rig.makeRecording(createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let kept = try rig.makeRecording(createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        // What the export made: the person's own file, outside the recordings, with the name of the recording it came from.
        let exported = rig.temporaryRoot.appending(path: "Movies/MyNotch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exported, withIntermediateDirectories: true)
        let video = exported.appending(path: "Bản quay MyNotch \(doomed.id.uuidString).mp4")
        try Data(count: 500).write(to: video)
        await module.refreshRecordings()

        module.deleteRecording(try #require(module.state.recordings.first { $0.id == doomed.id }))
        await rig.waitUntil { module.state.recordings.map(\.id) == [kept.id] }

        #expect(module.state.recordings.map(\.id) == [kept.id])
        #expect(!FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: doomed.id).path))
        #expect(FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: kept.id).appending(path: "segment-001.mov").path))
        #expect(FileManager.default.fileExists(atPath: video.path))
        // Nothing else of the module's was touched.
        #expect(FileManager.default.fileExists(atPath: rig.recordingsRoot.path))
    }

    @Test func theRecordingBeingMadeCannotBeDeleted() async throws {
        await rig.start()
        try await record()
        await rig.waitUntil { !module.state.recordings.isEmpty }
        let live = try #require(module.state.recordings.first)
        let toasts = harness.presenter.toastCount

        module.deleteRecording(live)
        await rig.waitUntil { harness.presenter.toastCount == toasts + 1 }

        #expect(FileManager.default.fileExists(atPath: live.folder.path))
        #expect(module.state.recordings.map(\.id) == [live.id])
    }

    @Test func aRecordingOpenInTheEditorCannotBeDeletedUntilItIsClosed() async throws {
        await rig.start()
        let project = try rig.makeRecording()
        await module.refreshRecordings()
        let summary = try #require(module.state.recordings.first)
        module.openRecording(summary)
        let toasts = harness.presenter.toastCount

        module.deleteRecording(summary)
        await rig.waitUntil { harness.presenter.toastCount == toasts + 1 }
        #expect(FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: project.id).path))

        editors.close(folder: summary.folder)
        module.deleteRecording(summary)
        await rig.waitUntil { module.state.recordings.isEmpty }
        #expect(!FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: project.id).path))
    }

    // MARK: Stopping the module

    @Test func stoppingTheModuleWhileRecordingClosesTheRecordingAndTheEditors() async throws {
        await rig.start()
        let other = try rig.makeRecording()
        await module.refreshRecordings()
        module.openRecording(try #require(module.state.recordings.first { $0.id == other.id }))
        try await record()
        let id = try #require(recorder.currentRecordingID)

        await harness.registry.setEnabled(false, for: "screenshot")

        #expect(recorder.stopCount == 1)
        #expect(editors.closeAllCount == 1 && rig.activity == nil && harness.registry.menuItems.isEmpty)
        // The recording is kept, whole, and not opened: the module is going away.
        #expect(try RecordingProject.load(from: rig.recordingStore.folder(for: id)).status == .finished)
        #expect(editors.opened.count == 1 && module.state.recordings.isEmpty && rig.phase == .idle)
    }

    @Test func stoppingTheModuleDuringTheCountdownCancelsItAndStartsNothing() async throws {
        await rig.start()
        await beginCounting()

        await harness.registry.setEnabled(false, for: "screenshot")
        harness.scheduler.advance(by: .seconds(10))

        #expect(recorder.starts.isEmpty && recorder.stopCount == 0 && rig.phase == .idle && rig.activity == nil)
    }

    @Test func stoppingTheModuleWhileTheStreamStartsEndsTheRecordingThatStartsAfterwards() async throws {
        await rig.start()
        recorder.isStartGated = true
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .starting }

        let stopping = Task { await harness.registry.setEnabled(false, for: "screenshot") }
        try await Task.sleep(for: .milliseconds(30))
        recorder.releaseStart()
        await stopping.value

        #expect(recorder.starts.count == 1 && recorder.stopCount == 1 && rig.phase == .idle && recorder.state == .idle)
    }

    @Test func stoppingTheModuleWhileSelectingLeavesNoPhaseBehind() async throws {
        await rig.start()
        rig.overlay.isGated = true
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        module.beginRecording(.region)
        await rig.waitUntil { rig.overlay.runs.count == 1 }
        #expect(rig.phase == .selecting)

        await harness.registry.setEnabled(false, for: "screenshot")
        try await Task.sleep(for: .milliseconds(20))

        #expect(rig.phase == .idle && recorder.starts.isEmpty)
    }

    // MARK: A real session

    func finish() async throws {
        module.stopRecording()
        await rig.waitUntil { rig.phase == .idle }
        #expect(rig.phase == .idle)
    }
}

/// The module with a real session, fed by a fake source: the wiring that the fake recorder hides.
@Suite(.serialized, .timeLimit(.minutes(1))) final class ScreenshotModuleWiringTests {
    let source = FakeRecordingSource()
    let events = FakeActivityEvents()
    let clock = TestClock(1000)
    let editors = FakeRecordingEditors()
    /// The session the module made, to wait for what it was fed.
    let made = SessionBox()
    let rig: ModuleRig

    final class SessionBox {
        var session: RecordingSession?
    }

    init() throws {
        let source = source, events = events, clock = clock, editors = editors, made = made
        rig = try ModuleRig(recording: RecordingDependencies(
            makeRecorder: { store, context in
                let session = RecordingSession(
                    source: source, events: events, permissions: context.permissions, store: store, scheduler: context.scheduler,
                    clock: clock.closure, engineOptions: .init(fragmentInterval: 2, requireHardwareEncoder: true, backpressure: .wait)
                )
                made.session = session
                return session
            },
            makeEditors: { _ in editors },
            pointerLocation: { .zero },
            microphones: { [] }
        ))
    }

    @Test func aRecordingIsMadeInTheModulesOwnFolderWithWhatTheSettingsSay() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        settings.set(true, for: keys.recordSystemAudio)
        settings.set(ExportLevel.high, for: keys.exportLevel)
        // Big enough for the hardware encoder.
        rig.overlay.result = .region(displayID: 1, pixelRect: CGRect(x: 0, y: 0, width: 128, height: 72))

        rig.module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .recording }
        #expect(rig.phase == .recording)

        // What the source was asked for.
        let configuration = try #require(source.configurations.first)
        #expect(configuration.region.pixelRect == CGRect(x: 0, y: 0, width: 128, height: 72))
        #expect(configuration.options == RecordingOptions(microphone: .systemDefault, systemAudio: true, fps: 60))
        // Where it is written: the module's own `Recordings` folder, never the caches.
        let folders = try FileManager.default.contentsOfDirectory(at: rig.recordingsRoot, includingPropertiesForKeys: nil)
        #expect(folders.count == 1 && UUID(uuidString: folders[0].lastPathComponent) != nil)
        #expect(!FileManager.default.fileExists(atPath: rig.storage.cachesDirectory.appending(path: "Recordings").path))
        #expect(try RecordingProject.load(from: folders[0]).status == .recording)
        #expect(!rig.module.menuItems.isEmpty)

        // A second of picture, and then the stop.
        for index in 0..<30 {
            source.deliver(RecordingMediaFactory.frame(width: 128, height: 72, index: index), at: clock.now)
            clock.advance(by: 1 / 30)
        }
        await source.settle()
        await made.session?.settle()
        rig.module.stopRecording()
        await rig.waitUntil { !editors.opened.isEmpty }

        #expect(editors.opened.map { $0.resolvingSymlinksInPath() } == [folders[0].resolvingSymlinksInPath()])
        let project = try RecordingProject.load(from: folders[0])
        #expect(project.status == .finished && project.segments.count == 1 && project.exportLevel == .high)
        #expect(rig.phase == .idle && rig.module.menuItems.isEmpty && rig.activity == nil)
        #expect(events.stopCount == 1 && source.stopCount == 1)
    }

    @Test func aRecordingNothingCameInIsNotKeptAndTheModuleSaysSo() async throws {
        await rig.start()
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        rig.module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .recording }

        rig.module.stopRecording()
        await rig.waitUntil { rig.phase == .idle }

        #expect(editors.opened.isEmpty && rig.harness.presenter.toastCount == 1)
        let folders = (try? FileManager.default.contentsOfDirectory(at: rig.recordingsRoot, includingPropertiesForKeys: nil)) ?? []
        #expect(folders.isEmpty)
    }

    @Test func withoutTheScreenPermissionTheSessionRefusesAndNothingIsCreated() async throws {
        await rig.start()
        rig.harness.permissions.statuses[.screenRecording] = .denied
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)

        rig.module.beginRecording(.region)
        await rig.waitUntil { rig.harness.presenter.toastCount == 1 }

        #expect(source.configurations.isEmpty && rig.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: rig.recordingsRoot.path) || ((try? FileManager.default.contentsOfDirectory(atPath: rig.recordingsRoot.path)) ?? []).isEmpty)
    }
}
