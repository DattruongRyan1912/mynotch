import CoreGraphics
import MyNotchCore

/// Decides from the user's input when a selection may just have been made, and when whatever is showing for one may be
/// stale. It only decides: nothing is read here, and the read waits for a short pause so a drag, a double click or a run
/// of shift-arrows costs one read, not one per event.
final class SelectionWatcher {
    /// The pause after the last gesture before the selection is read.
    static let debounce = Duration.milliseconds(250)
    /// A press and release this far apart (in points) is a drag; less is a click.
    static let dragDistance: CGFloat = 4

    private let scheduler: any Scheduler
    private let onSelection: @MainActor (CGPoint) -> Void
    private let onDismiss: @MainActor () -> Void
    private var pending: ScheduledAction?
    private var pressedAt: CGPoint?
    private var isStopped = false

    /// - Parameters:
    ///   - onSelection: a selection may be there to read, after the pause; the point is where the pointer was.
    ///   - onDismiss: the selection may be changing, so what was shown for the last one should go.
    init(scheduler: any Scheduler, onSelection: @escaping @MainActor (CGPoint) -> Void, onDismiss: @escaping @MainActor () -> Void) {
        self.scheduler = scheduler
        self.onSelection = onSelection
        self.onDismiss = onDismiss
    }

    func handle(_ input: SelectionInput) {
        guard !isStopped else { return }
        switch input {
        case .mouseDown(let point):
            // A new press begins a new gesture: a read still waiting is about a selection that is going away.
            pressedAt = point
            cancelPending()
            onDismiss()
        case .mouseUp(let point, let clicks):
            let start = pressedAt
            pressedAt = nil
            // A double or triple click selects a word or a line; a drag selects what it crosses; a click selects nothing.
            if clicks >= 2 || start.map({ Self.distance($0, point) >= Self.dragDistance }) == true {
                schedule(at: point)
            }
        case .keyUp(let key, let pointer):
            if key.changesSelection {
                schedule(at: pointer)
            } else {
                // Typing, the caret moving, Esc: the selection is probably gone or replaced.
                cancelPending()
                onDismiss()
            }
        case .applicationActivated:
            break
        }
    }

    func stop() {
        isStopped = true
        cancelPending()
    }

    private func schedule(at point: CGPoint) {
        pending?.cancel()
        pending = scheduler.schedule(after: Self.debounce) { [weak self] in
            self?.pending = nil
            self?.onSelection(point)
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
