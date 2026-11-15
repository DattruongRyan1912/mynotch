import MyNotchCore

/// Re-reads a battery that was not readable when the device connected: earbuds often report it a moment later.
/// The first read comes before the shortest activity duration (1 s) and the last before the default one (2.5 s), so
/// an update lands in the activity still on screen instead of appearing as a new one.
final class BluetoothBatteryRetry {
    /// When to read again, counted from the connection.
    static let readTimes: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]

    private let scheduler: any Scheduler
    private var pending: [String: [ScheduledAction]] = [:]

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    /// Calls `deliver` once with the first battery `read` returns, and stops reading after that or after the last read time.
    func start(key: String, read: @escaping @MainActor () -> BluetoothBattery?, deliver: @escaping @MainActor (BluetoothBattery) -> Void) {
        cancel(key: key)
        pending[key] = Self.readTimes.map { time in
            scheduler.schedule(after: time) { [weak self] in
                guard let battery = read() else { return }
                self?.cancel(key: key)
                deliver(battery)
            }
        }
    }

    func cancel(key: String) {
        pending.removeValue(forKey: key)?.forEach { $0.cancel() }
    }

    func cancelAll() {
        pending.values.joined().forEach { $0.cancel() }
        pending = [:]
    }
}
