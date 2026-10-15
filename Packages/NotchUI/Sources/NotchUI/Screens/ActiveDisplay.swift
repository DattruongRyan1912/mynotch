import CoreGraphics
import MyNotchCore

/// The display the user is working on: the one the pointer is on, once it has stayed there for `settleDelay`. A pointer
/// that only crosses another display, or goes there and comes back, never moves it, so the notch does not flicker
/// from one display to the other. `ScreenManager` feeds it the pointer and the displays.
final class ActiveDisplay {
    /// How long the pointer has to stay on another display before the notch follows.
    static let settleDelay: Duration = .milliseconds(300)

    /// The settled display; nil until the displays are known.
    private(set) var current: CGDirectDisplayID?
    private let scheduler: any Scheduler
    private let delay: Duration
    private let onChange: () -> Void
    private var displays: Set<CGDirectDisplayID> = []
    /// The display the pointer is on while it waits to be followed, and the timer for it.
    private var pending: (display: CGDirectDisplayID, timer: ScheduledAction)?

    init(scheduler: any Scheduler, delay: Duration = ActiveDisplay.settleDelay, onChange: @escaping () -> Void) {
        self.scheduler = scheduler
        self.delay = delay
        self.onChange = onChange
    }

    /// The pointer is now on `display`, nil between displays (which changes nothing). Called for every pointer move, so
    /// staying on one display costs a comparison.
    func pointerMoved(onto display: CGDirectDisplayID?) {
        guard let display else { return }
        if display == current {
            cancelPending()
            return
        }
        // Moving about on the new display does not restart the wait.
        guard pending?.display != display else { return }
        cancelPending()
        pending = (display, scheduler.schedule(after: delay) { [weak self] in self?.settle(on: display) })
    }

    /// The displays that exist now, in the system's order, and the one the pointer is on. A change of the set (plugged
    /// in, unplugged, woken) moves to the pointer's display at once, since nothing flickers when displays come and go;
    /// the same set again changes nothing.
    func displaysChanged(_ ids: [CGDirectDisplayID], pointerOn: CGDirectDisplayID?) {
        guard Set(ids) != displays else { return }
        displays = Set(ids)
        cancelPending()
        settle(on: pointerOn ?? ids.first)
    }

    /// Drops a move that is waiting.
    func stop() { cancelPending() }

    private func settle(on display: CGDirectDisplayID?) {
        pending = nil
        guard display != current else { return }
        current = display
        onChange()
    }

    private func cancelPending() {
        pending?.timer.cancel()
        pending = nil
    }
}
