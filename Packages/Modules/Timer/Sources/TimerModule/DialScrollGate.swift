import AppKit

/// Decides, event by event, whether a scroll over the dial turns it or goes on to the notch, which swipes between tabs
/// with the sideways scrolls that nobody else used. Like `TabSwipeRecognizer` it decides once per gesture, from how it
/// begins: a gesture that starts up and down is the dial's until it ends, anything else is never the dial's, so a
/// swipe that starts over the dial still reaches the notch, and a flick that drifts sideways keeps turning the dial.
/// Momentum, the coasting after the fingers lift, is never the dial's: it would carry the dial to an end.
nonisolated struct DialScrollGate {
    enum Action: Equatable {
        /// Not the dial's: the view passes the event on up the responder chain.
        case forward
        /// The dial's, but it moves no whole minute yet.
        case consume
        /// The dial's, and it moves this many minutes (up is more).
        case minutes(Int)
    }

    /// Until a gesture has travelled this far, which way it goes is not decided; the same distance as for tab swipes.
    static let lockDistance = 8.0

    private enum Axis {
        case undecided, vertical, ignored
    }

    private var scroll = DialScroll()
    private var isTracking = false
    private var axis = Axis.undecided
    private var travelX = 0.0
    private var travelY = 0.0
    /// Up and down travel not yet turned into minutes: what an undecided gesture covered before it was the dial's.
    private var unspent = 0.0

    mutating func feed(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: Double, deltaY: Double, isPrecise: Bool) -> Action {
        guard momentumPhase.isEmpty else { return .forward }
        // A mouse wheel has no gesture: each notch is judged alone.
        if phase.isEmpty {
            return abs(deltaY) > abs(deltaX) ? minutes(forDelta: deltaY, isPrecise: isPrecise) : .forward
        }
        if phase.contains(.began) {
            self = DialScrollGate()
            isTracking = true
        }
        // Touches that have not moved, or a gesture another view started and this one never saw begin.
        guard isTracking else { return .forward }
        if phase.contains(.ended) || phase.contains(.cancelled) { isTracking = false }
        travelX += deltaX
        travelY += deltaY
        unspent += deltaY
        if axis == .undecided, max(abs(travelX), abs(travelY)) >= Self.lockDistance {
            axis = abs(travelY) > abs(travelX) ? .vertical : .ignored
        }
        guard axis == .vertical else { return .forward }
        let delta = unspent
        unspent = 0
        return minutes(forDelta: delta, isPrecise: isPrecise)
    }

    private mutating func minutes(forDelta delta: Double, isPrecise: Bool) -> Action {
        let minutes = scroll.minutes(forTicks: DialScroll.ticks(forDelta: delta, isPrecise: isPrecise))
        return minutes == 0 ? .consume : .minutes(minutes)
    }
}
