import AVFoundation
import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

@Suite(.serialized, .timeLimit(.minutes(1))) struct RecordingSessionTests {
    let fixture: RecordingFixture
    var session: RecordingSession { fixture.session }

    init() throws { fixture = try RecordingFixture() }

    func segmentURL(_ project: RecordingProject, _ index: Int) -> URL {
        fixture.store.folder(for: project.id).appending(path: project.segments[index].fileName)
    }

    // MARK: A recording

    @Test func aRecordingIsASegmentWithPictureAndSoundAndAProjectBesideIt() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(2)
        let project = try await session.stop()

        #expect(project.status == .finished)
        #expect(project.segments.count == 1)
        #expect(project.segments[0].fileName == "segment-001.mov")
        #expect(abs(project.duration - 2) < 0.001)
        #expect(project.segments[0].frames == 60 && project.segments[0].droppedFrames == 0)
        #expect(project.region == fixture.region && project.fps == 60 && project.hasMicrophone && !project.hasSystemAudio)
        let probe = try await MediaProbe.read(segmentURL(project, 0))
        #expect(probe.videoSize == CGSize(width: 128, height: 72))
        #expect(probe.videoFrames == 60)
        #expect(probe.audioDurations.count == 1)
        #expect(abs(probe.duration - 2) < 0.1)
        // What is on disk is what was returned.
        let folder = fixture.store.folder(for: project.id)
        #expect(try RecordingProject.load(from: folder) == project)
        #expect(try ActivityTrack.load(from: folder).pixelWidth == 128)
        #expect(session.state == .idle && session.lastProject == project)
    }

    @Test func theSourceIsToldTheRegionAndWhatToCapture() async throws {
        try await session.start(region: fixture.region, options: .init(microphone: .device("USB-1"), systemAudio: true, fps: 30))

        let configuration = try #require(fixture.source.configurations.first)
        #expect(configuration.region == fixture.region)
        #expect(configuration.options == RecordingOptions(microphone: .device("USB-1"), systemAudio: true, fps: 30))
        _ = try? await session.stop()
    }

    @Test func theProjectIsOnDiskAsRecordingFromTheMomentTheStreamRuns() async throws {
        try await session.start(region: fixture.region)

        let folder = try #require(fixture.recordingFolders.first)
        let project = try RecordingProject.load(from: folder)
        #expect(project.status == .recording)
        #expect(project.segments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "segment-001.mov").path))
        #expect(try ActivityTrack.load(from: folder).pointer.isEmpty)
        #expect(session.state == .recording)
        #expect(session.currentRecordingID?.uuidString == folder.lastPathComponent)
        _ = try? await session.stop()
        #expect(session.currentRecordingID == nil)
    }

    @Test func anEventStampedAtAFramesTimeLandsOnThatFrameOfTheFile() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(0.5)
        // The clock is now the moment frame 15 is shown.
        fixture.events.click(.left, at: CGPoint(x: 10, y: 62))
        fixture.events.key()
        await fixture.play(0.5)
        let project = try await session.stop()

        let track = try ActivityTrack.load(from: fixture.store.folder(for: project.id))
        let probe = try await MediaProbe.read(segmentURL(project, 0))
        let frameTime = probe.videoTimes[15] - probe.videoTimes[0]
        #expect(track.clicks.count == 1 && track.keys.count == 1)
        #expect(abs(track.clicks[0].t - frameTime) < 0.002)
        #expect(abs(track.keys[0] - frameTime) < 0.002)
        // AppKit (10, 62) on a 72-pt display is 10 px from the left and 10 px down.
        #expect(track.clicks[0].x == 10 && track.clicks[0].y == 10)
    }

    @Test func theSamePlaceHoldsWhenTheStreamsClockIsNotTheHostClock() async throws {
        fixture.source.captureClockOffset = 250
        try await session.start(region: fixture.region)
        await fixture.play(0.5)
        fixture.events.click(.right, at: CGPoint(x: 20, y: 52))
        await fixture.play(0.5)
        let project = try await session.stop()

        let track = try ActivityTrack.load(from: fixture.store.folder(for: project.id))
        let probe = try await MediaProbe.read(segmentURL(project, 0))
        #expect(abs(track.clicks[0].t - (probe.videoTimes[15] - probe.videoTimes[0])) < 0.002)
        #expect(track.clicks[0].button == .right)
        #expect(abs(project.duration - 1) < 0.001)
    }

    // MARK: Pause

    @Test func aPauseCutsTheRecordingIntoTwoSegmentsAndTheActivityFollowsTheVideo() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(1)
        await session.pause()
        #expect(session.state == .paused)
        // Five seconds of nothing: events and frames in the pause are not part of the recording.
        fixture.clock.advance(by: 2)
        fixture.events.click(.left, at: CGPoint(x: 5, y: 5))
        fixture.events.key()
        await fixture.play(0.5)
        try await session.resume()
        #expect(session.state == .recording)
        await fixture.play(0.5)
        fixture.events.click(.left, at: CGPoint(x: 30, y: 40))
        await fixture.play(1)
        let project = try await session.stop()

        #expect(project.segments.map(\.fileName) == ["segment-001.mov", "segment-002.mov"])
        #expect(abs(project.segments[0].duration - 1) < 0.001)
        #expect(abs(project.segments[1].duration - 1.5) < 0.001)
        let first = try await MediaProbe.read(segmentURL(project, 0))
        let second = try await MediaProbe.read(segmentURL(project, 1))
        #expect(abs(first.duration - 1) < 0.1 && abs(second.duration - 1.5) < 0.1)
        #expect(first.videoFrames == 30)
        // Sound and picture of each segment end together.
        #expect(abs((first.audioDurations.first ?? 0) - first.duration) < 0.1)
        #expect(abs((second.audioDurations.first ?? 0) - second.duration) < 0.1)
        let track = try ActivityTrack.load(from: fixture.store.folder(for: project.id))
        #expect(track.clicks.count == 1 && track.keys.isEmpty)
        // 1 s of the first segment, then 0.5 s into the second.
        #expect(abs(track.clicks[0].t - 1.5) < 0.002)
        #expect(track.clicks[0].x == 30 && track.clicks[0].y == 32)
    }

    @Test func stoppingWhilePausedKeepsWhatWasRecordedBeforeThePause() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(1)
        await session.pause()
        fixture.clock.advance(by: 3)

        let project = try await session.stop()

        #expect(project.status == .finished && project.segments.count == 1)
        #expect(abs(project.duration - 1) < 0.001)
        #expect(session.state == .idle)
    }

    @Test func theElapsedTimeStopsDuringAPause() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(1)
        #expect(abs(session.elapsed - 1) < 0.001)
        await session.pause()
        fixture.clock.advance(by: 10)
        #expect(abs(session.elapsed - 1) < 0.001)
        try await session.resume()
        fixture.clock.advance(by: 0.25)
        #expect(abs(session.elapsed - 1.25) < 0.001)
        _ = try? await session.stop()
    }

    @Test func pausingWhenNotRecordingOrResumingWhenNotPausedDoesNothing() async throws {
        await session.pause()
        try await session.resume()
        #expect(session.state == .idle)
        try await session.start(region: fixture.region)
        try await session.resume()
        #expect(session.state == .recording)
        _ = try? await session.stop()
    }

    @Test func aSecondStartWhileRecordingIsRefused() async throws {
        try await session.start(region: fixture.region)

        await #expect(throws: RecordingError.alreadyRecording) { try await session.start(region: fixture.region) }

        #expect(fixture.recordingFolders.count == 1)
        _ = try? await session.stop()
    }

    @Test func aScreenThatDoesNotChangeStillGetsPictureAndSoundOnTheFileEveryHalfSecond() async throws {
        try await session.start(region: fixture.region)
        // One frame, then a still screen for 2 s while the microphone says nothing at all.
        fixture.source.deliver(RecordingMediaFactory.frame(width: 128, height: 72), at: fixture.clock.now)
        await fixture.settle()
        for _ in 0..<4 {
            fixture.clock.advance(by: 0.5)
            fixture.scheduler.advance(by: .milliseconds(500))
        }
        await fixture.settle()
        let project = try await session.stop()

        #expect(abs(project.duration - 2) < 0.001)
        #expect(project.segments[0].frames >= 4)
        let probe = try await MediaProbe.read(segmentURL(project, 0))
        #expect(probe.videoFrames >= 4)
        #expect(abs((probe.audioDurations.first ?? 0) - 2) < 0.1)
    }

    @Test func theProjectAndTheActivityAreSavedEveryFiveSecondsWhileRecording() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(1)
        fixture.events.click(.left, at: CGPoint(x: 1, y: 1))
        let folder = try #require(fixture.recordingFolders.first)
        #expect(try ActivityTrack.load(from: folder).clicks.isEmpty)

        for _ in 0..<9 { fixture.scheduler.advance(by: .milliseconds(500)) }
        await fixture.settle()
        #expect(try ActivityTrack.load(from: folder).clicks.isEmpty)
        fixture.scheduler.advance(by: .milliseconds(500))
        await fixture.settle()

        #expect(try ActivityTrack.load(from: folder).clicks.count == 1)
        #expect(try RecordingProject.load(from: folder).status == .recording)
        _ = try? await session.stop()
    }

    // MARK: Permissions and failures

    @Test func withoutScreenRecordingNothingIsCreatedAndNothingStarts() async throws {
        fixture.permissions.statuses[.screenRecording] = .denied

        await #expect(throws: RecordingError.screenRecordingDenied) { try await session.start(region: fixture.region) }

        #expect(fixture.recordingFolders.isEmpty)
        #expect(fixture.source.configurations.isEmpty)
        #expect(fixture.events.sink == nil)
        #expect(session.state == .idle)
        #expect(fixture.permissions.requested.isEmpty)
    }

    @Test func aDeniedMicrophoneIsRefusedBeforeAnythingIsCreated() async throws {
        fixture.permissions.statuses[.microphone] = .denied

        await #expect(throws: RecordingError.microphoneDenied) { try await session.start(region: fixture.region) }

        #expect(fixture.recordingFolders.isEmpty)
        #expect(fixture.source.configurations.isEmpty)
        #expect(session.state == .idle)
        // It was not asked again: only the system can change a refusal.
        #expect(fixture.permissions.requested.isEmpty)
    }

    @Test func aMicrophoneNeverAskedAboutIsAskedOnceAndRecordingGoesOnWhenAllowed() async throws {
        fixture.permissions.statuses[.microphone] = .notDetermined
        fixture.permissions.requestResult = .granted

        try await session.start(region: fixture.region)

        #expect(fixture.permissions.requested == [.microphone])
        #expect(session.state == .recording)
        _ = try? await session.stop()
    }

    @Test func aMicrophoneRefusedWhenAskedStopsTheRecordingBeforeItStarts() async throws {
        fixture.permissions.statuses[.microphone] = .notDetermined
        fixture.permissions.requestResult = .denied

        await #expect(throws: RecordingError.microphoneDenied) { try await session.start(region: fixture.region) }

        #expect(fixture.recordingFolders.isEmpty)
        #expect(session.state == .idle)
    }

    @Test func withoutAMicrophoneNoMicrophonePermissionIsNeededAndNoSoundTrackIsWritten() async throws {
        fixture.permissions.statuses[.microphone] = .denied

        try await session.start(region: fixture.region, options: .init(microphone: nil))
        await fixture.play(1, microphone: false)
        let project = try await session.stop()

        #expect(!project.hasMicrophone)
        let probe = try await MediaProbe.read(segmentURL(project, 0))
        #expect(probe.audioDurations.isEmpty)
        #expect(fixture.permissions.requested.isEmpty)
    }

    @Test func withoutAccessibilityOnlyTheMouseIsRecorded() async throws {
        fixture.permissions.statuses[.accessibility] = .denied

        try await session.start(region: fixture.region)
        #expect(fixture.events.includesKeys == false)
        await fixture.play(0.5)
        fixture.events.click(.left, at: CGPoint(x: 3, y: 3))
        fixture.events.key()
        await fixture.play(0.5)
        let project = try await session.stop()

        let track = try ActivityTrack.load(from: fixture.store.folder(for: project.id))
        #expect(!track.keyboardRecorded && track.keys.isEmpty && track.clicks.count == 1)
    }

    @Test func withAccessibilityKeysAreNoticed() async throws {
        try await session.start(region: fixture.region)

        #expect(fixture.events.includesKeys == true)
        _ = try? await session.stop()
    }

    @Test func aSystemThatRefusesTheStreamLeavesNoFolderBehind() async throws {
        fixture.source.startError = .screenRecordingDenied

        await #expect(throws: RecordingError.screenRecordingDenied) { try await session.start(region: fixture.region) }

        #expect(fixture.recordingFolders.isEmpty)
        #expect(fixture.source.stopCount == 1)
        #expect(session.state == .idle)
        #expect(fixture.events.sink == nil)
    }

    @Test func stoppingWithoutAFrameIsNoRecordingAndLeavesNoFile() async throws {
        try await session.start(region: fixture.region)

        await #expect(throws: RecordingError.nothingRecorded) { try await session.stop() }

        #expect(fixture.recordingFolders.isEmpty)
        #expect(session.state == .idle)
        #expect(session.lastProject == nil)
    }

    @Test func stoppingWhenNothingIsRecordingSaysSo() async {
        await #expect(throws: RecordingError.self) { try await session.stop() }
    }

    @Test func aRecordingCanFollowAnother() async throws {
        try await session.start(region: fixture.region)
        await fixture.play(0.5)
        let first = try await session.stop()
        try await session.start(region: fixture.region)
        await fixture.play(0.5)
        let second = try await session.stop()

        #expect(first.id != second.id)
        #expect(fixture.recordingFolders.count == 2)
    }

    // MARK: Ending by itself

    @Test func whenTheSystemStopsTheStreamWhatWasRecordedIsKeptAsFinished() async throws {
        var ended: [Result<RecordingProject, RecordingError>] = []
        session.onEnded = { ended.append($0) }
        try await session.start(region: fixture.region)
        await fixture.play(1)

        fixture.source.end(with: .stoppedBySystem)
        await fixture.source.settle()
        while ended.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        let project = try #require(try ended.first?.get())
        #expect(project.status == .finished)
        #expect(abs(project.duration - 1) < 0.1)
        #expect(session.state == .idle)
        #expect(fixture.events.sink == nil)
    }

    @Test func whenTheStreamFailsWhatWasRecordedIsRescuedAsIncomplete() async throws {
        var ended: [Result<RecordingProject, RecordingError>] = []
        session.onEnded = { ended.append($0) }
        try await session.start(region: fixture.region)
        await fixture.play(2)

        fixture.source.end(with: .failed("display went away"))
        await fixture.source.settle()
        while ended.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        let project = try #require(try ended.first?.get())
        #expect(project.status == .interrupted && project.isIncomplete)
        #expect(project.segments.count == 1 && project.duration > 1.5)
        #expect(try await MediaProbe.read(segmentURL(project, 0)).isPlayable)
    }

    @Test func aStreamThatNeverDeliversAFrameEndsTheRecordingInsteadOfRecordingNothing() async throws {
        var ended: [Result<RecordingProject, RecordingError>] = []
        session.onEnded = { ended.append($0) }
        try await session.start(region: fixture.region)

        // Five seconds of ticks with no picture at all.
        for _ in 0..<11 {
            fixture.clock.advance(by: 0.5)
            fixture.scheduler.advance(by: .milliseconds(500))
        }
        while ended.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        #expect(throws: RecordingError.nothingRecorded) { try ended[0].get() }
        #expect(fixture.recordingFolders.isEmpty)
        #expect(session.state == .idle)
        #expect(fixture.scheduler.pendingCount == 0)
    }

    @Test func aStreamThatFailsBeforeAnyFrameLeavesNothingAndSaysWhy() async throws {
        var ended: [Result<RecordingProject, RecordingError>] = []
        session.onEnded = { ended.append($0) }
        try await session.start(region: fixture.region)

        fixture.source.end(with: .failed("no display"))
        await fixture.source.settle()
        while ended.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        #expect(throws: RecordingError.failed("no display")) { try ended[0].get() }
        #expect(fixture.recordingFolders.isEmpty)
    }
}
