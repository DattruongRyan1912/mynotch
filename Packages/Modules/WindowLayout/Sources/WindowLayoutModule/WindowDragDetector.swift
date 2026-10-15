import CoreGraphics
import Foundation

/// The app a window belongs to, as the log and the notice name it: never a window title or anything inside the window.
nonisolated struct SnapApp: Equatable, Sendable {
    let bundleID: String?
    /// What the user knows the app as (`NSRunningApplication.localizedName`).
    let name: String?
}

/// A window of another app, as far as the module needs to know it. `frame` and `place` use Accessibility coordinates:
/// the origin is the top left of the primary display and y grows down.
protocol SnapWindow: AnyObject {
    var app: SnapApp { get }
    /// The window is minimised or its app is hidden: nobody sees it, wherever its frame says it is. A window on another
    /// Space is not told apart: Accessibility still answers for it, and the public ways to find out (the window list, which
    /// has to be matched to the element by its bounds, or what `kAXWindowsAttribute` leaves out) are neither permission-free
    /// nor documented.
    var isOutOfSight: Bool { get }
    /// Position and size, or nil when the app does not answer.
    func frame() -> CGRect?
    /// Moves and resizes the window to the placement, and keeps it inside the placement's visible area when the app does not
    /// take the size. False when the app refused to move.
    @discardableResult func place(_ placement: SnapPlacement) -> Bool
    func isSame(as other: any SnapWindow) -> Bool
}

/// Finds the window that has focus in the app in front.
protocol WindowProbe: AnyObject {
    func focusedWindow() -> (any SnapWindow)?
}

/// Tells a window being dragged from any other drag, such as selecting text or dragging a file: while the button is
/// down it looks at the focused window of the app in front now and then, and the drag is a window drag once that window
/// has moved (and kept its size, which a resize does not) between two looks.
///
/// Every look is a call into another app, so they are rare: at most one per `sampleInterval`, and only `maxSamples` of
/// them per press. A window drag shows within the first few, because the window follows the pointer from the start.
final class WindowDragDetector {
    static let sampleInterval: TimeInterval = 0.03
    static let maxSamples = 8
    /// An app that does not answer would block each look until the timeout, so two such looks end the watching.
    static let maxMisses = 2

    private struct Look {
        let window: any SnapWindow
        let frame: CGRect
    }

    private enum Phase {
        case idle
        case watching
        case recognised(any SnapWindow)
        case givenUp
    }

    private let probe: any WindowProbe
    private let isTrusted: () -> Bool
    private var phase = Phase.idle
    private var previous: Look?
    private var lastLook: TimeInterval?
    private var looks = 0
    private var misses = 0

    /// `isTrusted` is whether MyNotch has the Accessibility permission; it is read at every press, so a permission
    /// granted while the module runs works from the next press on.
    init(probe: any WindowProbe, isTrusted: @escaping () -> Bool) {
        self.probe = probe
        self.isTrusted = isTrusted
    }

    /// The window being dragged, once it is known to be one.
    var window: (any SnapWindow)? {
        if case .recognised(let window) = phase { window } else { nil }
    }

    var isDragging: Bool { window != nil }

    /// The button went down. Without the Accessibility permission nothing will be looked at.
    func mouseDown() {
        end()
        phase = isTrusted() ? .watching : .givenUp
    }

    /// The pointer moved with the button down, at `time` (seconds, any clock that only goes forward). True on the one
    /// call that shows the drag is a window drag.
    func mouseDragged(at time: TimeInterval) -> Bool {
        guard case .watching = phase else { return false }
        if let lastLook, time - lastLook < Self.sampleInterval { return false }
        lastLook = time
        looks += 1
        guard let window = probe.focusedWindow(), let frame = window.frame() else {
            previous = nil
            misses += 1
            if misses >= Self.maxMisses { phase = .givenUp }
            return false
        }
        misses = 0
        if let previous, previous.window.isSame(as: window), Self.moved(from: previous.frame, to: frame) {
            phase = .recognised(window)
            return true
        }
        previous = Look(window: window, frame: frame)
        if looks >= Self.maxSamples { phase = .givenUp }
        return false
    }

    /// The button went up, or the drag was cancelled.
    func end() {
        phase = .idle
        previous = nil
        lastLook = nil
        looks = 0
        misses = 0
    }

    /// Moved at least a point with the size unchanged: dragging a corner moves the origin too, but resizes.
    private static func moved(from old: CGRect, to new: CGRect) -> Bool {
        let sameSize = abs(new.width - old.width) < 1 && abs(new.height - old.height) < 1
        return sameSize && (abs(new.minX - old.minX) > 0.5 || abs(new.minY - old.minY) > 0.5)
    }
}
