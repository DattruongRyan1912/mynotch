@testable import SystemActivitiesModule

final class FakeVolumeMonitor: VolumeMonitoring {
    private var onChange: (@MainActor (VolumeState) -> Void)?
    func start(_ onChange: @escaping @MainActor (VolumeState) -> Void) { self.onChange = onChange }
    func stop() { onChange = nil }
    func send(level: Float, muted: Bool = false) { onChange?(VolumeState(level: level, muted: muted)) }
}

final class FakeBluetoothMonitor: BluetoothMonitoring {
    private var onEvent: (@MainActor (BluetoothEvent) -> Void)?
    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) { self.onEvent = onEvent }
    func stop() { onEvent = nil }
    func send(_ event: BluetoothEvent) { onEvent?(event) }
}
