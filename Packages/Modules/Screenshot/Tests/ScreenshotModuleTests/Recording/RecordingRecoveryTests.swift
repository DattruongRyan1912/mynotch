import AVFoundation
import Foundation
import Testing
@testable import ScreenshotModule

@Suite(.serialized, .timeLimit(.minutes(1))) struct RecordingRecoveryTests {
    let fixture: RecordingFixture
    /// Where the copies of a recording as a crash would have left it go: the same layout as the real recordings folder.
    let crashed: TestFolder

    init() throws {
        // A fragment every half second, so a few seconds of tiny frames leave several on disk.
        fixture = try RecordingFixture(fragmentInterval: 0.5)
        crashed = try TestFolder("crashed")
    }

    static func hasFragment(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return data.range(of: Data("moof".utf8)) != nil
    }

    /// Records for a few seconds and, while the writer is still open, copies the folder: the state of the disk if the app had been
    /// killed at that moment. The recording is then ended normally, so the test leaves nothing running.
    func crashImage(microphone: Bool = true, still: Bool = false) async throws -> (folder: URL, original: RecordingProject) {
        try await fixture.session.start(region: fixture.region)
        if still {
            await fixture.playStill(4)
        } else {
            await fixture.play(4, microphone: microphone)
        }
        let live = try #require(fixture.recordingFolders.first)
        let segment = live.appending(path: "segment-001.mov")
        let deadline = ContinuousClock.now + .seconds(10)
        while !Self.hasFragment(segment), ContinuousClock.now < deadline {
            await fixture.settle()
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(Self.hasFragment(segment), "the writer wrote no fragment")
        let image = crashed.file(live.lastPathComponent)
        try FileManager.default.copyItem(at: live, to: image)
        let project = try await fixture.session.stop()
        return (image, project)
    }

    @Test func aRecordingCutOffWhileWritingStillOpensUpToItsLastFragment() async throws {
        let (folder, original) = try await crashImage()
        // The image says what the disk said then: still being recorded, no segment closed.
        #expect(try RecordingProject.load(from: folder).status == .recording)
        #expect(try RecordingProject.load(from: folder).segments.isEmpty)

        let project = try await RecordingRecovery.recover(folder: folder)

        #expect(project.status == .interrupted && project.isIncomplete)
        #expect(project.segments.map(\.fileName) == ["segment-001.mov"])
        // Something between one fragment and everything that was recorded.
        #expect(project.duration > 0.3 && project.duration <= original.duration + 0.1)
        let probe = try await MediaProbe.read(folder.appending(path: "segment-001.mov"))
        #expect(probe.isPlayable && probe.videoFrames > 5)
        #expect(abs(probe.duration - project.duration) < 0.1)
        // What was saved says the same.
        #expect(try RecordingProject.load(from: folder) == project)
    }

    @Test func aMicrophoneThatDeliversNothingDoesNotKeepTheFileFromBeingRescued() async throws {
        // The microphone is on and never sends a buffer: the writer would hold the picture back for it and write no fragment.
        let (folder, _) = try await crashImage(microphone: false)

        let project = try await RecordingRecovery.recover(folder: folder)

        #expect(project.segments.count == 1 && project.duration > 0.3)
        let probe = try await MediaProbe.read(folder.appending(path: "segment-001.mov"))
        #expect(probe.isPlayable && probe.audioDurations.count == 1)
    }

    @Test func aScreenThatDoesNotChangeDoesNotKeepTheFileFromBeingRescued() async throws {
        // One picture and four seconds of speech: without the picture repeated, the writer waits for the next frame and the
        // sound piles up in memory instead of reaching the disk.
        let (folder, _) = try await crashImage(still: true)

        let project = try await RecordingRecovery.recover(folder: folder)

        #expect(project.segments.count == 1 && project.duration > 0.3)
        let probe = try await MediaProbe.read(folder.appending(path: "segment-001.mov"))
        #expect(probe.isPlayable && probe.videoFrames > 1)
    }

    @Test func aFileCutInsideItsLastBoxStillOpens() async throws {
        let (folder, _) = try await crashImage()
        let segment = folder.appending(path: "segment-001.mov")
        let data = try Data(contentsOf: segment)
        try data.prefix(data.count - 3000).write(to: segment)

        let project = try await RecordingRecovery.recover(folder: folder)

        #expect(project.segments.count == 1 && project.duration > 0.3)
        #expect(try await MediaProbe.read(segment).isPlayable)
    }

    @Test func theActivityKeepsWhatIsInTheRescuedVideoAndLosesWhatIsPastIt() async throws {
        let (folder, _) = try await crashImage()
        var track = try ActivityTrack.load(from: folder)
        track.clicks = [.init(t: 0.1, x: 1, y: 1, button: .left), .init(t: 100, x: 2, y: 2, button: .left)]
        track.keys = [0.2, 99]
        try track.write(to: folder)

        _ = try await RecordingRecovery.recover(folder: folder)

        let kept = try ActivityTrack.load(from: folder)
        #expect(kept.clicks.map(\.t) == [0.1])
        #expect(kept.keys == [0.2])
    }

    @Test func aSegmentThatNeverWroteItsFirstFragmentCannotBeReadAndIsLeftAlone() async throws {
        let folder = crashed.file(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = RecordingProject(
            id: UUID(uuidString: folder.lastPathComponent)!, createdAt: Date(timeIntervalSince1970: 1_000), status: .recording,
            region: fixture.region, fps: 60, hasMicrophone: true, hasSystemAudio: false
        )
        try project.write(to: folder)
        // An `ftyp` box and an `mdat` box that was still growing: no `moov`, so nothing says how to read it.
        var bytes = Data([0, 0, 0, 20]) + Data("ftypqt  ".utf8) + Data(count: 8)
        bytes += Data([0, 0, 0, 0]) + Data("mdat".utf8) + Data(repeating: 7, count: 4_000)
        let segment = folder.appending(path: "segment-001.mov")
        try bytes.write(to: segment)

        let recovered = try await RecordingRecovery.recover(folder: folder)

        #expect(recovered.segments.isEmpty && recovered.duration == 0)
        #expect(recovered.status == .interrupted)
        #expect(FileManager.default.fileExists(atPath: segment.path), "a recording's file is never deleted by the rescue")
    }

    @Test func aSegmentThatClosedProperlyKeepsWhatItsWriterMeasured() async throws {
        try await fixture.session.start(region: fixture.region)
        await fixture.play(1)
        await fixture.session.pause()
        try await fixture.session.resume()
        await fixture.play(2)
        // Cut the last segment's file like a crash would, after the first one was closed and saved.
        let live = try #require(fixture.recordingFolders.first)
        let deadline = ContinuousClock.now + .seconds(10)
        while !Self.hasFragment(live.appending(path: "segment-002.mov")), ContinuousClock.now < deadline {
            await fixture.settle()
            try await Task.sleep(for: .milliseconds(20))
        }
        // The pause saved the project with the first segment closed.
        await fixture.session.settle()
        let image = crashed.file(live.lastPathComponent)
        try FileManager.default.copyItem(at: live, to: image)
        _ = try await fixture.session.stop()

        let project = try await RecordingRecovery.recover(folder: image)

        #expect(project.segments.map(\.fileName) == ["segment-001.mov", "segment-002.mov"])
        #expect(abs(project.segments[0].duration - 1) < 0.001)
        #expect(project.segments[0].frames == 30)
        #expect(project.segments[1].captureStart == nil)
        #expect(project.segments[1].duration > 0.3)
    }

    @Test func aFolderWithoutAProjectCannotBeRescued() async throws {
        let folder = crashed.file(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        await #expect(throws: (any Error).self) { try await RecordingRecovery.recover(folder: folder) }
    }
}
