import MyNotchCore

/// Source of network path updates; faked in tests.
protocol PathSource: AnyObject {
    /// Calls `onUpdate` with the current path first, then on every change, until `stop()`.
    func start(_ onUpdate: @escaping @MainActor (NetworkStatus) -> Void)
    func stop()
}

/// Reports changes of connectivity or interface type, settled for a while so a flapping link emits once.
final class NetworkMonitor {
    private let source: any PathSource
    private let scheduler: any Scheduler
    private let debounce: Duration
    private var reported: NetworkStatus?
    private var pending: ScheduledAction?
    private var onChange: ((NetworkStatus) -> Void)?

    init(source: any PathSource, scheduler: any Scheduler, debounce: Duration = .seconds(1)) {
        self.source = source
        self.scheduler = scheduler
        self.debounce = debounce
    }

    /// The first update is the baseline, not a change.
    func start(_ onChange: @escaping (NetworkStatus) -> Void) {
        stop()
        self.onChange = onChange
        source.start { [weak self] in self?.receive($0) }
    }

    func stop() {
        source.stop()
        pending?.cancel()
        pending = nil
        reported = nil
        onChange = nil
    }

    private func receive(_ status: NetworkStatus) {
        guard reported != nil else {
            reported = status
            return
        }
        pending?.cancel()
        pending = scheduler.schedule(after: debounce) { [weak self] in
            guard let self, let reported, status.differs(from: reported) else { return }
            self.reported = status
            onChange?(status)
        }
    }
}
