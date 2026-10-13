@testable import SystemActivitiesModule

final class FakeVolumeMonitor: VolumeMonitoring {
    private var onChange: (@MainActor (VolumeState) -> Void)?
    var isRunning: Bool { onChange != nil }
    private(set) var startCount = 0
    func start(_ onChange: @escaping @MainActor (VolumeState) -> Void) { startCount += 1; self.onChange = onChange }
    func stop() { onChange = nil }
    func send(level: Float, muted: Bool = false) { onChange?(VolumeState(level: level, muted: muted)) }
}

final class FakeBluetoothMonitor: BluetoothMonitoring {
    private var onEvent: (@MainActor (BluetoothEvent) -> Void)?
    var isRunning: Bool { onEvent != nil }
    private(set) var startCount = 0
    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) { startCount += 1; self.onEvent = onEvent }
    func stop() { onEvent = nil }
    func send(_ event: BluetoothEvent) { onEvent?(event) }
}

final class FakeCapsLockMonitor: CapsLockMonitoring {
    private var onChange: ((Bool) -> Void)?
    var isRunning: Bool { onChange != nil }
    private(set) var startCount = 0
    func start(_ onChange: @escaping (Bool) -> Void) { startCount += 1; self.onChange = onChange }
    func stop() { onChange = nil }
    func send(_ isOn: Bool) { onChange?(isOn) }
}

final class FakeNetworkMonitor: NetworkMonitoring {
    private var onChange: ((NetworkStatus) -> Void)?
    var isRunning: Bool { onChange != nil }
    private(set) var startCount = 0
    func start(_ onChange: @escaping (NetworkStatus) -> Void) { startCount += 1; self.onChange = onChange }
    func stop() { onChange = nil }
    func send(_ status: NetworkStatus) { onChange?(status) }
}

final class FakeDownloadsWatcher: DownloadsWatching {
    private var onDownload: ((DownloadEvent) -> Void)?
    var isRunning: Bool { onDownload != nil }
    var canStart = true
    private(set) var startCount = 0
    func start(_ onDownload: @escaping (DownloadEvent) -> Void) -> Bool {
        startCount += 1
        guard canStart else { return false }
        self.onDownload = onDownload
        return true
    }
    func stop() { onDownload = nil }
    func send(_ event: DownloadEvent) { onDownload?(event) }
}
