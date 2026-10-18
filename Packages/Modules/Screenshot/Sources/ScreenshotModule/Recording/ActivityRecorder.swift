import CoreGraphics
import Foundation
import Synchronization

/// What an event source reports. Positions are AppKit global points; the recorder stamps each call with its own clock.
nonisolated protocol ActivityEventSink: AnyObject, Sendable {
    func pointerMoved(toAppKit point: CGPoint)
    func click(_ button: ClickButton, atAppKit point: CGPoint)
    /// That a key went down. Which key is never reported.
    func keyPressed()
}

/// Where pointer, click and key events come from; the real one reads the system, tests drive a fake.
protocol ActivityEventSource: AnyObject {
    /// Starts reporting to `sink`. Keys are only reported when `includesKeys`, which needs Accessibility.
    func start(sink: any ActivityEventSink, includesKeys: Bool)
    func stop()
}

/// Collects the pointer's path, the clicks and the moments keys went down, stamped with the clock the frames use, so the
/// session can later put each on the frame it belongs to. Events arrive on any thread.
nonisolated final class ActivityRecorder: ActivityEventSink {
    private struct Raw {
        var pointer: [(time: TimeInterval, point: CGPoint)] = []
        var clicks: [(time: TimeInterval, point: CGPoint, button: ClickButton)] = []
        var keys: [TimeInterval] = []
    }

    let region: RecordingRegion
    let recordsKeys: Bool
    private let clock: @Sendable () -> TimeInterval
    private let raw = Mutex(Raw())

    /// `clock` is the capture clock (the one frames are stamped with), injected so tests decide what time it is.
    init(region: RecordingRegion, recordsKeys: Bool, clock: @escaping @Sendable () -> TimeInterval) {
        self.region = region
        self.recordsKeys = recordsKeys
        self.clock = clock
    }

    func pointerMoved(toAppKit point: CGPoint) {
        let time = clock()
        let pixel = region.pixelPoint(forAppKit: point)
        raw.withLock { raw in
            // A pointer that did not move is no activity, and a still one would fill the file at 60 samples a second.
            guard raw.pointer.last?.point != pixel else { return }
            raw.pointer.append((time, pixel))
        }
    }

    func click(_ button: ClickButton, atAppKit point: CGPoint) {
        let time = clock()
        let pixel = region.pixelPoint(forAppKit: point)
        raw.withLock { $0.clicks.append((time, pixel, button)) }
    }

    func keyPressed() {
        guard recordsKeys else { return }
        let time = clock()
        raw.withLock { $0.keys.append(time) }
    }

    /// Everything seen so far, in recording time. Events outside every segment (before the first frame, inside a pause) are left
    /// out, except that each segment opens with where the pointer was at that moment, since it may not have moved since.
    func track(on timeline: RecordingTimeline) -> ActivityTrack {
        let raw = raw.withLock { $0 }
        let moves = raw.pointer.sorted { $0.time < $1.time }
        var track = ActivityTrack(pixelWidth: region.pixelWidth, pixelHeight: region.pixelHeight, keyboardRecorded: recordsKeys)
        var offset: TimeInterval = 0
        for segment in timeline.segments {
            if let last = moves.last(where: { $0.time < segment.start }) {
                track.pointer.append(.init(t: Self.milliseconds(offset), x: Self.tenth(last.point.x), y: Self.tenth(last.point.y)))
            }
            offset += segment.duration ?? 0
        }
        for event in moves {
            if let t = timeline.recordingTime(forCaptureTime: event.time) {
                track.pointer.append(.init(t: Self.milliseconds(t), x: Self.tenth(event.point.x), y: Self.tenth(event.point.y)))
            }
        }
        track.pointer.sort { $0.t < $1.t }
        for event in raw.clicks {
            if let t = timeline.recordingTime(forCaptureTime: event.time) {
                track.clicks.append(.init(t: Self.milliseconds(t), x: Self.tenth(event.point.x), y: Self.tenth(event.point.y), button: event.button))
            }
        }
        for time in raw.keys {
            if let t = timeline.recordingTime(forCaptureTime: time) { track.keys.append(Self.milliseconds(t)) }
        }
        return track
    }

    /// The file is read by eye as often as by code, and a millisecond is finer than a frame.
    private static func milliseconds(_ value: TimeInterval) -> TimeInterval { (value * 1000).rounded() / 1000 }
    private static func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
