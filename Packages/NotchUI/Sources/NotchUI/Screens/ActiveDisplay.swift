import CoreGraphics
import MyNotchCore

/// The display the user is working on: the one the pointer moved onto, once it has stayed there for `settleDelay`, or
/// the one the app that just came to the front shows its window on, at once. A pointer that only crosses another
/// display, or goes there and comes back, never moves it, so the notch does not flicker from one display to the other.
/// `ScreenManager` feeds it the pointer, the displays and the apps that come to the front.
final class ActiveDisplay {
    /// How long the pointer has to stay on another display before the notch follows.
    static let settleDelay: Duration = .milliseconds(300)

    /// The settled display; nil until the displays are known.
    private(set) var current: CGDirectDisplayID?
    private let scheduler: any Scheduler
    private let delay: Duration
    private let onChange: () -> Void
    private var displays: Set<CGDirectDisplayID> = []
    /// The display the pointer was last seen on: only a change of it is a move to another display, so a pointer that
    /// stays on one display does not undo what an app coming to the front decided.
    private var pointerDisplay: CGDirectDisplayID?
    /// The display the pointer is on while it waits to be followed, and the timer for it.
    private var pending: (display: CGDirectDisplayID, timer: ScheduledAction)?

    init(scheduler: any Scheduler, delay: Duration = ActiveDisplay.settleDelay, onChange: @escaping () -> Void) {
        self.scheduler = scheduler
        self.delay = delay
        self.onChange = onChange
    }

    /// The pointer is now on `display`, nil between displays (which changes nothing). Called for every pointer move, so
    /// staying on one display costs a comparison, and moving about on the new display does not restart the wait.
    func pointerMoved(onto display: CGDirectDisplayID?) {
        guard let display, display != pointerDisplay else { return }
        pointerDisplay = display
        cancelPending()
        guard display != current else { return }
        pending = (display, scheduler.schedule(after: delay) { [weak self] in self?.settle(on: display) })
    }

    /// An app came to the front and its window is on `display` (nil when it has none): the user is working there, so the
    /// notch follows at once, which also drops a move the pointer had started.
    func activated(on display: CGDirectDisplayID?) {
        guard let display else { return }
        cancelPending()
        settle(on: display)
    }

    /// The displays that exist now, in the system's order, and the one the pointer is on. A change of the set (plugged
    /// in, unplugged, woken) moves to the pointer's display at once, since nothing flickers when displays come and go;
    /// the same set again changes nothing.
    func displaysChanged(_ ids: [CGDirectDisplayID], pointerOn: CGDirectDisplayID?) {
        guard Set(ids) != displays else { return }
        displays = Set(ids)
        pointerDisplay = pointerOn
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
