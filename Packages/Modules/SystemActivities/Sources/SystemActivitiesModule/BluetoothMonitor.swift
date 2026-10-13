import Foundation
import IOBluetooth
import MyNotchCore

/// Source of Bluetooth connect/disconnect events; faked in tests.
protocol BluetoothMonitoring: AnyObject {
    /// Calls `onEvent` when a device connects or disconnects, until `stop()`. Devices that are already
    /// connected are not reported. A connection whose battery was not readable yet is reported once more
    /// when it becomes readable.
    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void)
    func stop()
}

/// Watches IOBluetooth connect notifications and a disconnect notification per device.
/// Starting it is what first touches Bluetooth, so the permission prompt belongs to `start`. The first IOBluetooth
/// call blocks until the user answers it, so `start` makes that call off the main thread and registers afterwards.
final class BluetoothMonitor: NSObject, BluetoothMonitoring {
    private var onEvent: (@MainActor (BluetoothEvent) -> Void)?
    private var starting: Task<Void, Never>?
    private var tracker = BluetoothConnectionTracker(connectedAtStart: [String]())
    private let batteryRetry: BluetoothBatteryRetry
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    init(scheduler: any Scheduler) {
        batteryRetry = BluetoothBatteryRetry(scheduler: scheduler)
    }

    isolated deinit { stop() }

    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        starting = Task { [weak self] in
            await Self.waitForAccessDecision()
            guard !Task.isCancelled else { return }
            self?.register()
        }
    }

    /// Once the user has decided, the calls in `register()` no longer block.
    @concurrent private static func waitForAccessDecision() async {
        autoreleasepool { _ = IOBluetoothDevice.pairedDevices() }
    }

    private func register() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        // Devices connected before start are not announced, but their disconnect still is.
        let connected = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }.filter { $0.isConnected() }
        tracker = BluetoothConnectionTracker(connectedAtStart: connected.map(Self.key))
        connected.forEach(watchDisconnect)
    }

    func stop() {
        starting?.cancel()
        starting = nil
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        batteryRetry.cancelAll()
        onEvent = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watchDisconnect(device)
        guard tracker.connected(Self.key(device)) else { return }
        let battery = BluetoothBattery.read(from: device)
        emit(device, connected: true, battery: battery)
        if battery == nil { retryBattery(of: device) }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        let key = Self.key(device)
        disconnectNotifications[key] = nil
        batteryRetry.cancel(key: key)
        tracker.disconnected(key)
        emit(device, connected: false, battery: nil)
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        let key = Self.key(device)
        guard disconnectNotifications[key] == nil,
              let notification = device.register(
                forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        else { return }
        disconnectNotifications[key] = notification
    }

    private func retryBattery(of device: IOBluetoothDevice) {
        batteryRetry.start(
            key: Self.key(device),
            read: { device.isConnected() ? BluetoothBattery.read(from: device) : nil },
            deliver: { [weak self] in self?.emit(device, connected: true, battery: $0) })
    }

    private func emit(_ device: IOBluetoothDevice, connected: Bool, battery: BluetoothBattery?) {
        onEvent?(BluetoothEvent(
            name: device.name ?? device.addressString ?? "Bluetooth",
            kind: BluetoothDeviceKind(major: device.deviceClassMajor, minor: device.deviceClassMinor),
            connected: connected,
            battery: battery))
    }

    private static func key(_ device: IOBluetoothDevice) -> String { device.addressString ?? "" }
}
