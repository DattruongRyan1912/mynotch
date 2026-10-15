import AppKit

/// How far two fingers have to travel, up or down, to open or close the notch. Stored by name.
nonisolated public enum SwipeSensitivity: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    /// Vertical travel, in points of scrolling delta, that makes a step: the less sensitive, the longer the swipe.
    var distance: CGFloat {
        switch self {
        case .low: 64
        case .medium: 40
        case .high: 24
        }
    }
}

/// Turns the scroll events of a two-finger vertical swipe over the notch into at most one step per gesture, the way
/// `TabSwipeRecognizer` does for a sideways one and with the same tuning: only finger phases count, momentum and a mouse
/// wheel never do, and which way a gesture goes is decided once, so a gesture is a tab swipe or this one and never both.
/// `deltaY` is the fingers' direction: positive is down.
nonisolated struct NotchSwipeRecognizer {
    enum Step: Equatable {
        case down, up
    }

    enum Action: Equatable {
        case open, close
    }

    static let lockDistance = TabSwipeRecognizer.lockDistance
    /// A swipe goes at least this many times as far up or down as sideways when its direction is decided.
    static let verticalDominance = TabSwipeRecognizer.horizontalDominance

    private enum Axis {
        case undecided, vertical, ignored
    }

    private var isTracking = false
    private var axis = Axis.undecided
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var hasStepped = false

    /// `onNotch` is whether the pointer is over the notch itself; it is read when a gesture begins, so a gesture that
    /// started elsewhere stays no one's business here even if the pointer reaches the notch, and one that started on the
    /// notch goes on if the pointer leaves it. `sensitivity` is read at every event, as the setting can change.
    mutating func feed(
        phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat, onNotch: Bool, sensitivity: SwipeSensitivity
    ) -> Step? {
        guard momentumPhase.isEmpty else { return nil }
        if phase.contains(.began) {
            self = NotchSwipeRecognizer()
            isTracking = onNotch
        }
        // A mouse wheel (no phase), touches that have not moved, or a gesture that began elsewhere or in another view.
        guard isTracking, !phase.isEmpty else { return nil }
        if phase.contains(.ended) || phase.contains(.cancelled) { isTracking = false }
        guard !phase.contains(.cancelled) else { return nil }
        travelX += deltaX
        travelY += deltaY
        if axis == .undecided, max(abs(travelX), abs(travelY)) >= Self.lockDistance {
            axis = abs(travelY) >= Self.verticalDominance * abs(travelX) ? .vertical : .ignored
        }
        guard axis == .vertical, !hasStepped, abs(travelY) >= sensitivity.distance else { return nil }
        hasStepped = true
        return travelY > 0 ? .down : .up
    }
}

extension NotchSwipeRecognizer.Step {
    /// What this step does to a notch in `state`: down opens the collapsed notch, up closes the open one, and nothing else
    /// does anything (a toast belongs to whatever showed it). `keptOpen` is a pin or a drag in progress: what keeps the notch
    /// open against a click outside and against the pointer leaving keeps it open against a swipe too, which carries no
    /// more intent to close than those do. Opening is never held back.
    func action(state: NotchState, keptOpen: Bool = false) -> NotchSwipeRecognizer.Action? {
        switch (self, state) {
        case (.down, .closed), (.down, .compact): .open
        case (.up, .open): keptOpen ? nil : .close
        default: nil
        }
    }
}
