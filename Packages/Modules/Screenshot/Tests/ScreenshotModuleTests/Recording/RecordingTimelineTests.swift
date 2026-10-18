import CoreMedia
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct RecordingTimelineTests {
    /// Two segments: capture time 100 to 110, then (after a pause of 20 s) 130 to 135 and one still open from 200.
    let timeline = RecordingTimeline(segments: [
        .init(start: 100, duration: 10), .init(start: 130, duration: 5), .init(start: 200, duration: nil),
    ])

    @Test func aMomentInTheFirstSegmentIsItsOffsetFromTheStart() {
        #expect(timeline.recordingTime(forCaptureTime: 100) == 0)
        #expect(timeline.recordingTime(forCaptureTime: 104.5) == 4.5)
    }

    @Test func theTimeAfterAPauseContinuesWhereTheVideoStoppedNotWhereTheClockIs() {
        #expect(timeline.recordingTime(forCaptureTime: 130) == 10)
        #expect(timeline.recordingTime(forCaptureTime: 132.25) == 12.25)
    }

    @Test func aSegmentStillOpenReachesToTheEnd() {
        #expect(timeline.recordingTime(forCaptureTime: 200) == 15)
        let late = timeline.recordingTime(forCaptureTime: 5000)
        #expect(late == 4815)
    }

    @Test func aMomentBeforeTheFirstFrameInAPauseOrAtTheEndOfASegmentBelongsToNothing() {
        #expect(timeline.recordingTime(forCaptureTime: 99.999) == nil)
        #expect(timeline.recordingTime(forCaptureTime: 110) == nil)
        #expect(timeline.recordingTime(forCaptureTime: 120) == nil)
        #expect(timeline.recordingTime(forCaptureTime: 135) == nil)
        #expect(timeline.recordingTime(forCaptureTime: 199.9) == nil)
    }

    @Test func noSegmentsMeansNothingIsRecorded() {
        #expect(RecordingTimeline(segments: []).recordingTime(forCaptureTime: 1) == nil)
    }

    @Test func eventStampsAndFrameStampsShareOneClock() {
        // The clock the frames use is the host clock; what the activity is stamped with must be the same one, or every event lands
        // on the wrong frame. `ProcessInfo.systemUptime` is the same mach clock, so the two agree to well under a frame.
        let host = RecordingClock.now()
        let uptime = ProcessInfo.processInfo.systemUptime

        #expect(abs(host - uptime) < 0.05)
        #expect(host > 0)
    }

    @Test func aStreamClockThatIsTheHostClockNeedsNoOffset() {
        #expect(RecordingClock.offset(of: CMClockGetHostTimeClock()) == 0)
        #expect(RecordingClock.offset(of: nil) == 0)
    }
}
