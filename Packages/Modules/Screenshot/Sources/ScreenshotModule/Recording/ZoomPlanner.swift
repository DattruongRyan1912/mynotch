import CoreGraphics
import Foundation

/// Turns what the pointer and keyboard did into the stretches of a recording that are zoomed in. A pure function: the same
/// activity and rules always give the same plan, so the editor can plan again whenever the rules change.
///
/// Only a click starts a zoom. A click, a pointer that really moved, and a key keep it going, until `idleTimeout` has passed
/// with none of them. So typing right after a click stays zoomed in, and typing with no click before it does not zoom at all.
nonisolated enum ZoomPlanner {
    /// How often the pointer's place is kept as a point of the focus. The camera joins them by straight lines.
    static let focusInterval = 0.05

    /// `duration` is the length of the recording when it is known: nothing after it is looked at and no zoom runs past it.
    static func plan(activity: ActivityTrack, rules: ZoomRules = .standard, duration: TimeInterval? = nil) -> [ZoomSegment] {
        let events = Self.events(in: activity, before: duration)
        let frame = CGRect(x: 0, y: 0, width: activity.pixelWidth, height: activity.pixelHeight)

        // Walk the activity in time order, opening a zoom at a click and keeping it open while something keeps happening.
        var raw: [(start: TimeInterval, last: TimeInterval)] = []
        var open: (start: TimeInterval, last: TimeInterval)?
        var reference: CGPoint?
        for event in events {
            var isActivity = true
            switch event.kind {
            case .click:
                reference = event.point
            case .move:
                // The first position only says where the pointer is; after that a move counts once it is far enough from the
                // place of the last activity, so a resting hand does not hold a zoom open.
                if let ref = reference, let point = event.point {
                    isActivity = hypot(point.x - ref.x, point.y - ref.y) >= rules.minimumMovement
                } else {
                    isActivity = false
                }
                if isActivity || reference == nil { reference = event.point }
            case .key:
                break
            }
            if let current = open, event.time > current.last + rules.idleTimeout {
                raw.append(current)
                open = nil
            }
            guard isActivity else { continue }
            if open != nil {
                open?.last = event.time
            } else if event.kind == .click, let point = event.point, frame.contains(point) {
                open = (event.time, event.time)
            }
        }
        if let open { raw.append(open) }

        var segments: [ZoomSegment] = []
        for item in raw {
            var end = item.last + rules.idleTimeout
            if let duration { end = min(end, duration) }
            guard end > item.start else { continue }
            if let previous = segments.last, item.start - previous.end < rules.mergeGap {
                segments[segments.count - 1].end = end
            } else {
                segments.append(ZoomSegment(start: item.start, end: end, scale: rules.scale))
            }
        }
        for index in segments.indices {
            segments[index].focus = focus(for: segments[index], events: events)
        }
        return segments
    }

    /// A zoom the person adds at `time`, looking where the pointer was and followed while it moved.
    static func manualSegment(
        at time: TimeInterval, duration: TimeInterval = 3, scale: Double? = nil, activity: ActivityTrack, rules: ZoomRules = .standard
    ) -> ZoomSegment {
        var segment = ZoomSegment(start: time, end: time + duration, scale: scale ?? rules.scale, manual: true)
        let events = Self.events(in: activity, before: nil)
        var focus = Self.focus(for: segment, events: events.filter { $0.kind != .key })
        let place = pointerPlace(at: time, events: events)
            ?? CGPoint(x: Double(activity.pixelWidth) / 2, y: Double(activity.pixelHeight) / 2)
        if focus.first.map({ $0.t > time }) ?? true {
            focus.insert(.init(t: time, x: place.x, y: place.y), at: 0)
        }
        segment.focus = focus
        return segment
    }

    // MARK: Events

    private struct Event {
        enum Kind { case click, move, key }

        var time: TimeInterval
        var kind: Kind
        var point: CGPoint?
    }

    /// Everything that happened, in time order; a click comes before a move or a key at the same moment.
    private static func events(in activity: ActivityTrack, before duration: TimeInterval?) -> [Event] {
        var events: [Event] = []
        events.reserveCapacity(activity.pointer.count + activity.clicks.count + activity.keys.count)
        events += activity.clicks.map { Event(time: $0.t, kind: .click, point: CGPoint(x: $0.x, y: $0.y)) }
        events += activity.pointer.map { Event(time: $0.t, kind: .move, point: CGPoint(x: $0.x, y: $0.y)) }
        events += activity.keys.map { Event(time: $0, kind: .key, point: nil) }
        if let duration { events.removeAll { $0.time >= duration } }
        func rank(_ kind: Event.Kind) -> Int { kind == .click ? 0 : kind == .move ? 1 : 2 }
        events.sort { ($0.time, rank($0.kind)) < ($1.time, rank($1.kind)) }
        return events
    }

    /// The clicks inside a zoom and the pointer a few times a second, sorted, one point per moment. A click is exact; a
    /// pointer sample is kept only when `focusInterval` has passed since the last one kept.
    private static func focus(for segment: ZoomSegment, events: [Event]) -> [ZoomSegment.Focus] {
        var points: [ZoomSegment.Focus] = []
        var lastSample = -Double.infinity
        for event in events where event.time >= segment.start && event.time <= segment.end {
            guard let point = event.point else { continue }
            if event.kind == .click {
                points.append(.init(t: event.time, x: point.x, y: point.y))
            } else if event.time - lastSample >= focusInterval - 1e-6 {
                lastSample = event.time
                points.append(.init(t: event.time, x: point.x, y: point.y))
            }
        }
        // Events are in time order and a click sorts first, so a pointer sample at a click's moment is the later one.
        var result: [ZoomSegment.Focus] = []
        for point in points where result.last.map({ point.t - $0.t > 1e-9 }) ?? true {
            result.append(point)
        }
        return result
    }

    /// Where the pointer was at `time`: the last place it was seen at or before then, or the first one after when it had
    /// not been seen yet.
    private static func pointerPlace(at time: TimeInterval, events: [Event]) -> CGPoint? {
        let places = events.filter { $0.point != nil }
        return (places.last { $0.time <= time } ?? places.first { $0.time > time })?.point
    }
}
