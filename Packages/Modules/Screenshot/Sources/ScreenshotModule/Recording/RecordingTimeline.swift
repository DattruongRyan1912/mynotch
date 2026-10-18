import CoreMedia
import Foundation

/// Reads the clock the frames are stamped with: the host clock, seconds since boot without the time asleep.
nonisolated enum RecordingClock {
    static func now() -> TimeInterval { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    /// Seconds to add to the host clock to get `clock`, the clock ScreenCaptureKit stamps its samples with. Nothing when it
    /// is the host clock, which is what it uses; this is the guard in case it ever is not.
    static func offset(of clock: CMClock?) -> TimeInterval {
        guard let clock else { return 0 }
        let host = CMClockGetHostTimeClock()
        let now = CMClockGetTime(host)
        return CMSyncConvertTime(now, from: host, to: clock).seconds - now.seconds
    }
}

/// Where each segment sits on the capture clock, and so which video time an event belongs to. Pauses are the gaps between
/// segments: they take no time in the recording, and an event inside one belongs to nothing.
nonisolated struct RecordingTimeline: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        /// On the capture clock, the stamp of the segment's first frame.
        var start: TimeInterval
        /// Nil while the segment is still being written.
        var duration: TimeInterval?
    }

    var segments: [Segment]

    /// Seconds into the recording, counted over the segments only, for a moment on the capture clock; nil when that moment
    /// is before the first frame, inside a pause or after the end.
    func recordingTime(forCaptureTime time: TimeInterval) -> TimeInterval? {
        var offset: TimeInterval = 0
        for segment in segments {
            if time >= segment.start, segment.duration.map({ time < segment.start + $0 }) ?? true {
                return offset + (time - segment.start)
            }
            offset += segment.duration ?? 0
        }
        return nil
    }
}
