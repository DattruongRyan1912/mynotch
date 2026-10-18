import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct RecordingCompositionTests {
    /// Second `k` of the recording is a flat grey of its own, and sounds a tone of its own loudness.
    static func level(of second: Int) -> UInt8 { UInt8(30 + 25 * second) }
    static func loudness(of second: Int) -> Double { 0.05 + 0.1 * Double(second) }

    static func sample(parts: [SampleRecording.Part], width: Int = 160, height: Int = 90, sound: Bool = true) async throws -> SampleRecording {
        try await SampleRecording.make(
            parts: parts, width: width, height: height,
            picture: { PixelBuffers.solid(width: width, height: height, grey: level(of: Int($0 + 1e-6))) },
            amplitude: sound ? { Float(loudness(of: Int($0 + 1e-6))) } : nil
        )
    }

    /// The grey a frame of the edited video should have, given where in the recording it comes from.
    func expectGrey(_ frame: CompositionProbe.Frame, second: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = Int(Self.level(of: second))
        #expect(abs(Int(frame.pixels[0].g) - expected) <= 8, "at \(frame.time): grey \(frame.pixels[0].g), wanted about \(expected)", sourceLocation: sourceLocation)
    }

    func expectLoud(_ samples: [Float], from start: Double, to end: Double, second: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let expected = Self.loudness(of: second) / 2.0.squareRoot()
        let measured = CompositionProbe.rms(samples, from: start, to: end)
        #expect(abs(measured - expected) < expected * 0.2 + 0.01, "\(start)-\(end): \(measured), wanted about \(expected) (second \(second))", sourceLocation: sourceLocation)
    }

    // MARK: Time

    @Test func theEditedVideoIsAsLongAsWhatIsKeptAndEachFrameComesFromTheRightMoment() async throws {
        // Two segments of 3 s (a pause between them), seconds 0-5 of the recording.
        var recording = try await Self.sample(parts: [.init(seconds: 3), .init(seconds: 3)])
        // 1.5 s to 4.5 s out: from the middle of the first segment into the middle of the second.
        recording.project.cuts = [CutRange(start: 1.5, end: 4.5)]

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(80, 45)])

        #expect(abs(built.duration - 3) < 0.02)
        #expect(abs(built.composition.duration.seconds - 3) < 0.02)
        #expect(frames.count == 60)
        for (index, frame) in frames.enumerated() {
            #expect(abs(frame.time - Double(index) / 20) < 1e-6)
            let time = frame.time < 1.5 ? frame.time : frame.time + 3
            expectGrey(frame, second: Int(time + 1e-6))
        }
    }

    @Test func soundAndPictureChangeTogetherAtEveryEdgeOfACut() async throws {
        var recording = try await Self.sample(parts: [.init(seconds: 3), .init(seconds: 3)])
        recording.project.cuts = [CutRange(start: 1.5, end: 4.5)]

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(80, 45)])
        let sound = try await CompositionProbe.samples(of: built)

        // The edited video, in seconds: 0-1 second 0, 1-1.5 second 1, 1.5-2 second 4 (its second half), 2-3 second 5.
        // Just before and just after each edge, the picture and the sound belong to the same second.
        let edges: [(at: Double, before: Int, after: Int)] = [(1, 0, 1), (1.5, 1, 4), (2, 4, 5)]
        for edge in edges {
            let before = try #require(frames.first { abs($0.time - (edge.at - 0.05)) < 1e-6 })
            let after = try #require(frames.first { abs($0.time - edge.at) < 1e-6 })
            expectGrey(before, second: edge.before)
            expectGrey(after, second: edge.after)
            expectLoud(sound, from: edge.at - 0.17, to: edge.at - 0.06, second: edge.before)
            expectLoud(sound, from: edge.at + 0.06, to: edge.at + 0.17, second: edge.after)
        }
        // The sound ends with the picture.
        #expect(abs(Double(sound.count) / 48_000 - 3) < 0.1)
    }

    @Test func aPauseBetweenSegmentsLeavesNoGapAndNoOverlapInPictureOrSound() async throws {
        let recording = try await Self.sample(parts: [.init(seconds: 3), .init(seconds: 2.5), .init(seconds: 2)])

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(80, 45)])
        let sound = try await CompositionProbe.samples(of: built)

        #expect(abs(built.duration - 7.5) < 0.02)
        for frame in frames { expectGrey(frame, second: Int(frame.time + 1e-6)) }
        for second in [1, 2, 3, 4, 5, 6] {
            // The middle of each second, which is inside one segment or another, never on a join.
            expectLoud(sound, from: Double(second) + 0.3, to: Double(second) + 0.7, second: second)
        }
        // Where the segments meet (3 s and 5.5 s) the sound goes from one second's loudness to the next at the join.
        expectLoud(sound, from: 2.85, to: 2.95, second: 2)
        expectLoud(sound, from: 3.06, to: 3.16, second: 3)
        expectLoud(sound, from: 5.35, to: 5.45, second: 5)
        expectLoud(sound, from: 5.56, to: 5.66, second: 5)
    }

    @Test func pieceBoundariesAreMetExactlyEvenForCutsThatFallBetweenTicks() async throws {
        var recording = try await Self.sample(parts: [.init(seconds: 2), .init(seconds: 2)])
        recording.project.cuts = [CutRange(start: 0.3333333, end: 0.7777777), CutRange(start: 1.9999999, end: 2.0000001), CutRange(start: 3.1415926, end: 3.5)]

        let built = try await recording.compose()

        for track in [built.videoTrack] + built.audioTracks {
            let segments = track.segments
            #expect(segments.count >= 3)
            #expect(segments.allSatisfy { !$0.isEmpty })
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(a.timeMapping.target.end == b.timeMapping.target.start, "a gap or an overlap in the composition")
            }
        }
        let kept = recording.project.duration - (0.4444444 + 0.0000002 + 0.3584074)
        #expect(abs(built.duration - kept) < 0.001)
    }

    @Test func theCameraAndTheRingsFollowTheRecordingsTimeNotTheEditedVideosTime() async throws {
        // A zoom on the lower right of a 320×180 picture that starts at 4.6 s of the recording, then a cut from 1.5 s to 4.5 s:
        // the zoom is in the edited video from 1.6 s, and 2.6 s of it is 5.6 s of the recording, well into the zoom.
        let (width, height) = (320, 180)
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 3), .init(seconds: 3)], width: width, height: height,
            picture: { _ in Self.gradient(width: width, height: height) }
        )
        recording.project.cuts = [CutRange(start: 1.5, end: 4.5)]
        recording.project.zoomSegments = [ZoomSegment(start: 4.6, end: 20, scale: 2, focus: [.init(t: 4.6, x: 300, y: 170)])]

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(160, 90), (0, 0)])

        // Before the zoom the middle of the output is the middle of the picture (x 160, y 90 of 320×180).
        let early = try #require(frames.first { abs($0.time - 1.4) < 1e-6 })
        #expect(abs(Int(early.pixels[0].b) - Self.blue(at: 160, width: width)) <= 8)
        #expect(abs(Int(early.pixels[0].g) - Self.green(at: 90, height: height)) <= 8)
        // Later it is the middle of the zoomed view: the view is 160×90 in the lower right corner, from (160, 90).
        let late = try #require(frames.first { abs($0.time - 2.6) < 1e-6 })
        #expect(abs(Int(late.pixels[0].b) - Self.blue(at: 240, width: width)) <= 8)
        #expect(abs(Int(late.pixels[0].g) - Self.green(at: 135, height: height)) <= 8)
        #expect(abs(Int(late.pixels[1].b) - Self.blue(at: 160, width: width)) <= 10)
        #expect(abs(Int(late.pixels[1].g) - Self.green(at: 90, height: height)) <= 10)
    }

    // MARK: Cadence

    @Test func theOutputIsTimedByTheCompositionsFrameDurationNotByTheFramesInTheFile() async throws {
        // A screen that stood still: the file has a frame every half second. At 30 fps the output still has a frame every 1/30 s,
        // and the camera zooming over it moves in every one of them.
        let (width, height) = (320, 180)
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 3, frameInterval: 0.5)], width: width, height: height,
            picture: { _ in Self.gradient(width: width, height: height) }
        )
        recording.project.zoomSegments = [ZoomSegment(start: 1, end: 10, scale: 2, focus: [.init(t: 1, x: 300, y: 170)])]

        let built = try await recording.compose(.init(frameRate: 30))
        let frames = try await CompositionProbe.frames(of: built, at: [(160, 90)])

        #expect(frames.count == 90)
        for (index, frame) in frames.enumerated() { #expect(abs(frame.time - Double(index) / 30) < 1e-6) }
        // Frames 31 to 45 are inside the zoom-in (1 s to 1.5 s): each is further right than the one before it.
        try #require(frames.count == 90, "the frame count is the first thing to break when the output follows the file's frames")
        let blues = frames[30...45].map { Int($0.pixels[0].b) }
        for (before, after) in zip(blues, blues.dropFirst()) { #expect(after >= before, "the camera stood still in a frame: \(blues)") }
        #expect(Set(blues).count >= 8, "the camera moved in too few frames: \(blues)")
    }

    @Test func theFrameRateAndTheSizeOfTheOutputAreWhatWasAskedFor() async throws {
        let recording = try await Self.sample(parts: [.init(seconds: 2)], sound: false)

        let built = try await recording.compose(.init(renderSize: CGSize(width: 80, height: 44), frameRate: 10))

        #expect(built.renderSize == CGSize(width: 80, height: 44) && built.frameRate == 10)
        #expect(built.videoComposition.renderSize == CGSize(width: 80, height: 44))
        #expect(built.videoComposition.frameDuration == CMTime(value: 1, timescale: 10))
        let frames = try await CompositionProbe.frames(of: built, at: [(40, 22)])
        #expect(frames.count == 20)
        // The recording's own size and rate when nothing is asked.
        let plain = try await recording.compose()
        #expect(plain.renderSize == CGSize(width: 160, height: 90) && plain.frameRate == 30)
    }

    // MARK: Zoom and rings

    static func gradient(width: Int, height: Int) -> CVPixelBuffer {
        PixelBuffers.make(width: width, height: height) { x, y in (UInt8(x * 255 / width), UInt8(y * 255 / height), 40) }
    }

    static func blue(at x: Int, width: Int) -> Int { x * 255 / width }
    static func green(at y: Int, height: Int) -> Int { y * 255 / height }

    @Test func aZoomShowsTheFocusedPartTheRightWayUp() async throws {
        let (width, height) = (320, 180)
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 4)], width: width, height: height, picture: { _ in Self.gradient(width: width, height: height) }
        )
        // The upper right: the view settles at 160×90 with its left edge at 160 and its top edge at 0.
        recording.project.zoomSegments = [ZoomSegment(start: 0.5, end: 10, scale: 2, focus: [.init(t: 0.5, x: 300, y: 20)])]

        let built = try await recording.compose(.init(frameRate: 10))
        let frames = try await CompositionProbe.frames(of: built, at: [(0, 0), (319, 0), (0, 179), (160, 90)])

        let settled = try #require(frames.first { abs($0.time - 3) < 1e-6 })
        #expect(abs(Int(settled.pixels[0].b) - Self.blue(at: 160, width: width)) <= 8 && abs(Int(settled.pixels[0].g) - 0) <= 8)
        #expect(abs(Int(settled.pixels[1].b) - Self.blue(at: 319, width: width)) <= 8)
        #expect(abs(Int(settled.pixels[2].g) - Self.green(at: 90, height: height)) <= 8)
        #expect(abs(Int(settled.pixels[3].b) - Self.blue(at: 240, width: width)) <= 8 && abs(Int(settled.pixels[3].g) - Self.green(at: 45, height: height)) <= 8)
        // At the start nothing is zoomed: the corner is the corner of the picture.
        let first = try #require(frames.first)
        #expect(Int(first.pixels[0].b) <= 8 && Int(first.pixels[0].g) <= 8)
    }

    /// A grey 640×360 picture with a click at an asymmetric place, so a ring is easy to find and a flipped one is not where it
    /// should be.
    func ringRecording(clickEffect: Bool = true, zoom: ZoomSegment? = nil) async throws -> SampleRecording {
        let click = ActivityTrack.Click(t: 3, x: 160, y: 90, button: .left)
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 5, frameInterval: 0.25)], width: 640, height: 360, clicks: [click],
            picture: { _ in PixelBuffers.solid(width: 640, height: 360, grey: 60) }
        )
        recording.project.clickEffect = clickEffect
        recording.project.zoomSegments = zoom.map { [$0] } ?? []
        return recording
    }

    @Test func aRingShowsAtTheMomentOfTheClickAndOnlyThen() async throws {
        let recording = try await ringRecording()
        let side = 360.0
        let onRing = (Int(160 + side * 0.014), 90)   // the ring's own radius at the click, to the right of its middle

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [onRing, (480, 90), (160, 270)])

        let before = try #require(frames.first { abs($0.time - 2.95) < 1e-6 })
        let at = try #require(frames.first { abs($0.time - 3.0) < 1e-6 })
        let after = try #require(frames.first { abs($0.time - 3.6) < 1e-6 })
        #expect(abs(Int(before.pixels[0].g) - 60) <= 6)
        #expect(at.pixels[0].g > 160, "the ring is not on the click at the moment of the click: \(at.pixels[0])")
        #expect(abs(Int(at.pixels[1].g) - 60) <= 6 && abs(Int(at.pixels[2].g) - 60) <= 6, "a ring where there was no click")
        #expect(abs(Int(after.pixels[0].g) - 60) <= 6)
    }

    @Test func noRingShowsWhenTheEffectIsOff() async throws {
        let recording = try await ringRecording(clickEffect: false)

        let built = try await recording.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(165, 90)])

        for frame in frames { #expect(abs(Int(frame.pixels[0].g) - 60) <= 6, "at \(frame.time)") }
    }

    @Test func aRingIsDrawnWhereTheZoomedCameraSeesTheClick() async throws {
        // The camera sits on the click for a view of half the size: the click is in the middle of the output and the ring is
        // twice as big, 10 px to the right of the middle at the moment of the click.
        let zoom = ZoomSegment(start: 0.5, end: 10, scale: 2, focus: [.init(t: 0.5, x: 160, y: 90)])
        let recording = try await ringRecording(zoom: zoom)

        let built = try await recording.compose(.init(frameRate: 20))
        // The view is the upper left quarter: the click at (160, 90) is at (320, 180) in the output.
        let frames = try await CompositionProbe.frames(of: built, at: [(320 + 10, 180), (160 + 5, 90), (320, 180 + 60)])

        let at = try #require(frames.first { abs($0.time - 3.0) < 1e-6 })
        let before = try #require(frames.first { abs($0.time - 2.95) < 1e-6 })
        #expect(at.pixels[0].g > 160, "no ring at the click as the camera sees it: \(at.pixels[0])")
        #expect(abs(Int(at.pixels[1].g) - 60) <= 6, "the ring is where it would be without the zoom")
        #expect(abs(Int(before.pixels[0].g) - 60) <= 6)
    }

    @Test func aRingWhoseClickWasCutIsNotLeftHangingAfterTheCut() async throws {
        let recording = try await ringRecording()
        var cut = recording
        // The click is at 3 s; the cut takes 2.9 s to 3.2 s out, so what plays after it begins in the middle of the ring.
        cut.project.cuts = [CutRange(start: 2.9, end: 3.2)]

        let built = try await cut.compose(.init(frameRate: 20))
        let frames = try await CompositionProbe.frames(of: built, at: [(Int(160 + 360 * 0.03), 90)])

        // The edited video's 3.2 s - 0.3 s = 2.9 s is where the cut is: nothing there but the grey.
        for frame in frames where frame.time >= 2.85 && frame.time < 3.3 {
            #expect(abs(Int(frame.pixels[0].g) - 60) <= 6, "a ring after the cut at \(frame.time)")
        }
    }

    // MARK: Plan

    @Test func withoutEditedZoomsThePlanComesFromTheActivityAndTheRules() async throws {
        let (width, height) = (320, 180)
        var recording = try await SampleRecording.make(
            parts: [.init(seconds: 4)], width: width, height: height, clicks: [.init(t: 0.5, x: 300, y: 20, button: .left)],
            picture: { _ in Self.gradient(width: width, height: height) }
        )
        recording.project.zoomSegments = nil

        let built = try await recording.compose(.init(frameRate: 10))

        // A click at 0.5 s zooms in from there until 2 s, and out by about 2.6 s.
        #expect(built.camera.hasZoom)
        #expect(abs(built.camera.rect(at: 1.5).width - 160) < 3)
        #expect(built.camera.rect(at: 3.5) == CGRect(x: 0, y: 0, width: 320, height: 180))
        // Zooms the person removed stay removed.
        recording.project.zoomSegments = []
        #expect(try await recording.compose().camera.hasZoom == false)
    }

    // MARK: Failures

    @Test func aMissingFileOrNoSegmentsOrNothingLeftIsAnErrorNotAnEmptyVideo() async throws {
        var recording = try await Self.sample(parts: [.init(seconds: 1), .init(seconds: 1)], sound: false)

        var empty = recording
        empty.project.segments = []
        await #expect(throws: RecordingCompositionError.noSegments) { try await empty.compose() }

        var allCut = recording
        allCut.project.cuts = [CutRange(start: 0, end: 5)]
        await #expect(throws: RecordingCompositionError.nothingLeft) { try await allCut.compose() }

        try FileManager.default.removeItem(at: recording.folder.file("segment-002.mov"))
        await #expect(throws: RecordingCompositionError.missingFile("segment-002.mov")) { try await recording.compose() }
        // A segment that is cut out entirely is never opened, so its file may be gone.
        recording.project.cuts = [CutRange(start: 1, end: 2)]
        #expect(abs(try await recording.compose().duration - 1) < 0.02)
    }

    @Test func aFileThatIsNotAMovieIsAMissingFile() async throws {
        var recording = try await Self.sample(parts: [.init(seconds: 1)], sound: false)
        try Data(count: 100).write(to: recording.folder.file("segment-001.mov"))
        recording.project.segments[0].fileName = "segment-001.mov"

        await #expect(throws: RecordingCompositionError.self) { try await recording.compose() }
    }

    @Test func aPlayerItemCarriesTheCompositionAndTheVideoComposition() async throws {
        let built = try await Self.sample(parts: [.init(seconds: 1)], sound: false).compose()

        let item = built.makePlayerItem()

        // The player item copies what it is given, so it is the same thing and not the same object.
        let videoComposition = try #require(item.videoComposition)
        #expect(videoComposition.customVideoCompositorClass is RecordingCompositor.Type)
        #expect(videoComposition.renderSize == built.renderSize && videoComposition.frameDuration == built.videoComposition.frameDuration)
        #expect(item.asset is AVComposition)
    }
}
