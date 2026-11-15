import AppKit
import MyNotchCore

/// Turns the scroll events of a two-finger sideways swipe into at most one step to the previous or next tab per
/// gesture. It is fed what a trackpad sends: finger phases (`began`, `changed`, `ended`), then momentum events with no
/// finger phase while the content coasts, and for a mouse wheel neither. Only the finger phases count, so momentum
/// never repeats a step.
nonisolated struct TabSwipeRecognizer {
    enum Step: Equatable {
        case previous, next
    }

    /// Sideways travel, in points of scrolling delta, that makes a step: enough that a brush of the trackpad does not.
    static let stepDistance: CGFloat = 40
    /// Until a gesture has travelled this far, which way it goes is not decided.
    static let lockDistance: CGFloat = 8
    /// A swipe goes at least this many times as far sideways as up or down when its direction is decided; anything
    /// else is a scroll (or a diagonal drag) that belongs to the content.
    static let horizontalDominance: CGFloat = 2

    private enum Axis {
        case undecided, horizontal, ignored
    }

    private var isTracking = false
    private var axis = Axis.undecided
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var hasStepped = false

    /// Positive `deltaX` is content moving right, which is the fingers moving right under natural scrolling: the
    /// previous tab then comes in from the left, as it does for any scroll view.
    mutating func feed(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat) -> Step? {
        guard momentumPhase.isEmpty else { return nil }
        if phase.contains(.began) {
            self = TabSwipeRecognizer()
            isTracking = true
        }
        // A mouse wheel (no phase), touches that have not moved, or a gesture another view started and this one never saw begin.
        guard isTracking, !phase.isEmpty else { return nil }
        if phase.contains(.ended) || phase.contains(.cancelled) { isTracking = false }
        guard !phase.contains(.cancelled) else { return nil }
        travelX += deltaX
        travelY += deltaY
        if axis == .undecided, max(abs(travelX), abs(travelY)) >= Self.lockDistance {
            axis = abs(travelX) >= Self.horizontalDominance * abs(travelY) ? .horizontal : .ignored
        }
        guard axis == .horizontal, !hasStepped, abs(travelX) >= Self.stepDistance else { return nil }
        hasStepped = true
        return travelX > 0 ? .previous : .next
    }
}

extension TabSwipeRecognizer.Step {
    /// The tab this step leads to from the open notch's tab, in the order of the tab bar; nil when it should do
    /// nothing: swiping is off (the app setting, or the system's own "swipe between pages"), the notch is not open on
    /// one of `tabs`, or the tab is already the first or last. `tabs` are the stops of the bar: the pages on it, then "Khác" as one stop,
    /// and `stop` says which stop a page is: itself, or "Khác" for a page in it, so a swipe from one of those goes to the stop before
    /// "Khác", and a swipe onto "Khác" opens its grid.
    func target(
        state: NotchState, tabs: [ModuleID], enabled: Bool, systemAllows: Bool, stop: (ModuleID) -> ModuleID = { $0 }
    ) -> ModuleID? {
        guard enabled, systemAllows, case .open(let page?) = state, let index = tabs.firstIndex(of: stop(page)) else { return nil }
        let neighbour = self == .next ? index + 1 : index - 1
        return tabs.indices.contains(neighbour) ? tabs[neighbour] : nil
    }
}
