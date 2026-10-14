import Foundation

/// The maths of the minute dial: a ring that is one hour round, a minute every six degrees, 12 o'clock is zero and the
/// hands go clockwise. Kept free of views so the angles, the snapping and the steps are checked with plain numbers.
nonisolated enum MinuteDial {
    static let range = 0...60
    static let degreesPerMinute = 6.0

    /// 360° for a full dial: the ring of 60 minutes closes where it began.
    static func angle(forMinutes minutes: Int) -> Double {
        Double(minutes) * degreesPerMinute
    }

    /// The whole minute nearest to `angle`, which may lie outside one turn. The top of the dial is both 0 and 60: while
    /// dragging, it is 60 when the pointer arrives from the high side (the ring was nearly full) and 0 from the low
    /// side, so passing 12 o'clock never snaps a full ring to empty. Going on past 60 wraps to 1, 2, ...
    static func minutes(forAngle angle: Double, previous: Int) -> Int {
        let turn = angle.truncatingRemainder(dividingBy: 360)
        let normalized = turn < 0 ? turn + 360 : turn
        let minutes = Int((normalized / degreesPerMinute).rounded()) % 60
        guard minutes == 0 else { return minutes }
        return previous >= 30 ? 60 : 0
    }

    /// Degrees clockwise from 12 o'clock, in [0, 360), of `point` seen from `center` in view coordinates (y grows
    /// downward). The center itself is at the top.
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let (dx, dy) = (point.x - center.x, point.y - center.y)
        guard dx != 0 || dy != 0 else { return 0 }
        let degrees = atan2(dx, -dy) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, range.lowerBound), range.upperBound)
    }

    /// Stops at the ends: an arrow key or a scroll cannot go round the dial.
    static func stepped(_ minutes: Int, by delta: Int) -> Int {
        clamped(minutes + delta)
    }

    /// Right (or up) adds, left subtracts; Shift makes the step five minutes.
    static func keyboardDelta(increase: Bool, shift: Bool) -> Int {
        (shift ? 5 : 1) * (increase ? 1 : -1)
    }

    /// How much of the ring a running timer fills: the minutes left out of an hour, never more than the full ring.
    static func fraction(remaining: TimeInterval) -> Double {
        min(max(remaining / 3_600, 0), 1)
    }

    /// What VoiceOver reads for a running timer: the minutes left, rounded up so the last minute is still one.
    static func spokenRemaining(seconds: TimeInterval) -> String {
        if seconds <= 0 { return "hết giờ" }
        if seconds < 60 { return "còn dưới 1 phút" }
        return "còn \(Int((seconds / 60).rounded(.up))) phút"
    }

    /// What VoiceOver reads while the length is being set.
    static func spokenSetting(minutes: Int) -> String {
        "\(minutes) phút"
    }
}

/// Turns a stream of scroll deltas into whole minutes, carrying the fraction over so a slow trackpad swipe still gets
/// there.
nonisolated struct DialScroll {
    /// A trackpad reports points, a wheel reports notches: a minute is this many points, or one notch. A light flick
    /// of two fingers is a few dozen points, so this keeps it to a few minutes.
    static let pointsPerMinute = 12.0

    private var carried = 0.0

    /// Scroll units in minutes: a precise (trackpad) delta is in points, a wheel delta already counts notches.
    static func ticks(forDelta delta: Double, isPrecise: Bool) -> Double {
        isPrecise ? delta / pointsPerMinute : delta
    }

    /// The whole minutes to move for this much scrolling; the rest is kept for the next call.
    mutating func minutes(forTicks ticks: Double) -> Int {
        carried += ticks
        let whole = carried.rounded(.towardZero)
        carried -= whole
        return Int(whole)
    }
}
