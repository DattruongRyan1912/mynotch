import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import ScreenshotModule

/// A clock a test moves by hand.
nonisolated final class TestClock: Sendable {
    private let value: Mutex<TimeInterval>
    init(_ start: TimeInterval = 1000) { value = Mutex(start) }
    var now: TimeInterval { value.withLock { $0 } }
    func set(_ time: TimeInterval) { value.withLock { $0 = time } }
    func advance(by seconds: TimeInterval) { value.withLock { $0 += seconds } }
    var closure: @Sendable () -> TimeInterval { { [self] in now } }
}

@Suite struct ActivityRecorderTests {
    static let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600), scale: 2)
    let clock = TestClock(1000)

    func makeRecorder(recordsKeys: Bool = true) throws -> ActivityRecorder {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 100, y: 100, width: 400, height: 300)))
        return ActivityRecorder(region: region, recordsKeys: recordsKeys, clock: clock.closure)
    }

    /// One segment from capture time 1000 to 1020, so recording time is capture time minus 1000.
    let whole = RecordingTimeline(segments: [.init(start: 1000, duration: 20)])

    @Test func pointerPositionsAreStampedWithTheCaptureClockAndMappedToTheVideo() throws {
        let recorder = try makeRecorder()
        clock.set(1001.5)
        // Region is x 100..500, y 100..400 (AppKit, y up) on a 2× display: its top-left is AppKit (100, 400).
        recorder.pointerMoved(toAppKit: CGPoint(x: 150, y: 350))

        let track = recorder.track(on: whole)

        #expect(track.pointer == [.init(t: 1.5, x: 100, y: 100)])
        #expect(track.pixelWidth == 800 && track.pixelHeight == 600)
    }

    @Test func aPointerThatDoesNotMoveAddsNothing() throws {
        let recorder = try makeRecorder()
        for second in 0..<10 {
            clock.set(1000 + Double(second) * 0.016)
            recorder.pointerMoved(toAppKit: CGPoint(x: 150, y: 350))
        }

        #expect(recorder.track(on: whole).pointer.count == 1)
    }

    @Test func leftAndRightClicksKeepTheirButtonAndPlace() throws {
        let recorder = try makeRecorder()
        clock.set(1002)
        recorder.click(.left, atAppKit: CGPoint(x: 200, y: 300))
        clock.set(1003)
        recorder.click(.right, atAppKit: CGPoint(x: 300, y: 200))

        let track = recorder.track(on: whole)

        #expect(track.clicks == [
            .init(t: 2, x: 200, y: 200, button: .left),
            .init(t: 3, x: 400, y: 400, button: .right),
        ])
    }

    @Test func aKeyIsOnlyAMoment() throws {
        let recorder = try makeRecorder()
        clock.set(1004.25)
        recorder.keyPressed()

        let track = recorder.track(on: whole)

        #expect(track.keys == [4.25])
        #expect(track.keyboardRecorded)
        // Nothing but numbers describes it: no field could carry what was typed.
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        #expect(Set(json.keys) == ["version", "pixelWidth", "pixelHeight", "keyboardRecorded", "pointer", "clicks", "keys"])
        #expect(json["keys"] as? [Double] == [4.25])
    }

    @Test func withoutAccessibilityOnlyThePointerIsRecorded() throws {
        let recorder = try makeRecorder(recordsKeys: false)
        clock.set(1001)
        recorder.keyPressed()
        recorder.pointerMoved(toAppKit: CGPoint(x: 150, y: 350))
        recorder.click(.left, atAppKit: CGPoint(x: 150, y: 350))

        let track = recorder.track(on: whole)

        #expect(track.keys.isEmpty)
        #expect(!track.keyboardRecorded)
        #expect(track.pointer.count == 1 && track.clicks.count == 1)
    }

    @Test func eventsInAPauseAreDroppedAndTheOnesAfterItFollowTheVideo() throws {
        let recorder = try makeRecorder()
        // Video from 1000 to 1010, a pause, video again from 1030.
        let timeline = RecordingTimeline(segments: [.init(start: 1000, duration: 10), .init(start: 1030, duration: 10)])
        clock.set(1005)
        recorder.click(.left, atAppKit: CGPoint(x: 200, y: 300))
        clock.set(1020)
        recorder.click(.left, atAppKit: CGPoint(x: 210, y: 300))
        recorder.keyPressed()
        clock.set(1032)
        recorder.click(.left, atAppKit: CGPoint(x: 220, y: 300))

        let track = recorder.track(on: timeline)

        #expect(track.clicks.map(\.t) == [5, 12])
        #expect(track.keys.isEmpty)
    }

    @Test func eachSegmentOpensWithWhereThePointerWasEvenIfItDidNotMoveSince() throws {
        let recorder = try makeRecorder()
        let timeline = RecordingTimeline(segments: [.init(start: 1000, duration: 10), .init(start: 1030, duration: 10)])
        clock.set(999)
        recorder.pointerMoved(toAppKit: CGPoint(x: 150, y: 350))
        clock.set(1020)
        recorder.pointerMoved(toAppKit: CGPoint(x: 250, y: 350))

        let track = recorder.track(on: timeline)

        // The pointer moved during the pause, to where the second segment starts; it is not re-reported inside the segment.
        #expect(track.pointer == [.init(t: 0, x: 100, y: 100), .init(t: 10, x: 300, y: 100)])
    }

    @Test func aSamplePreciselyAtASegmentStartIsNotReportedTwice() throws {
        let recorder = try makeRecorder()
        clock.set(1000)
        recorder.pointerMoved(toAppKit: CGPoint(x: 150, y: 350))

        #expect(recorder.track(on: whole).pointer.count == 1)
    }

    @Test func trimmingDropsWhatLiesBeyondTheRecoveredEnd() {
        let track = ActivityTrack(
            pixelWidth: 10, pixelHeight: 10, keyboardRecorded: true,
            pointer: [.init(t: 1, x: 0, y: 0), .init(t: 9, x: 0, y: 0)],
            clicks: [.init(t: 5, x: 0, y: 0, button: .left), .init(t: 7, x: 0, y: 0, button: .left)], keys: [3, 8]
        )

        let trimmed = track.trimmed(to: 6)

        #expect(trimmed.pointer.map(\.t) == [1])
        #expect(trimmed.clicks.map(\.t) == [5])
        #expect(trimmed.keys == [3])
    }

    @Test func theTrackIsWrittenAtomicallyAndReadBack() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MyNotchTests-activity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = try makeRecorder()
        clock.set(1001)
        recorder.click(.left, atAppKit: CGPoint(x: 200, y: 300))
        let track = recorder.track(on: whole)

        try track.write(to: folder)

        #expect(try ActivityTrack.load(from: folder) == track)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["activity.json"])
    }

    @Test func eventsFromManyThreadsAreAllKept() throws {
        let recorder = try makeRecorder()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in recorder.keyPressed() }

        #expect(recorder.track(on: whole).keys.count == 200)
    }
}
