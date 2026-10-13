import CoreGraphics
import MyNotchCore

/// Polls the Caps Lock state: reading it needs no permission, unlike a global key tap.
final class CapsLockMonitor {
    private let flags: () -> CGEventFlags
    private let scheduler: any Scheduler
    private let interval: Duration
    private var isOn = false
    private var onChange: ((Bool) -> Void)?
    private var nextTick: ScheduledAction?

    init(
        flags: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) },
        scheduler: any Scheduler, interval: Duration = .milliseconds(250)
    ) {
        self.flags = flags
        self.scheduler = scheduler
        self.interval = interval
    }

    /// The state at start is the baseline: only later changes are reported.
    func start(_ onChange: @escaping (_ isOn: Bool) -> Void) {
        stop()
        self.onChange = onChange
        isOn = flags().contains(.maskAlphaShift)
        scheduleTick()
    }

    func stop() {
        nextTick?.cancel()
        nextTick = nil
        onChange = nil
    }

    /// Schedules the next tick first, so a `stop()` from the callback cancels it.
    private func tick() {
        scheduleTick()
        let current = flags().contains(.maskAlphaShift)
        guard current != isOn else { return }
        isOn = current
        onChange?(current)
    }

    private func scheduleTick() {
        nextTick = scheduler.schedule(after: interval) { [weak self] in self?.tick() }
    }
}
