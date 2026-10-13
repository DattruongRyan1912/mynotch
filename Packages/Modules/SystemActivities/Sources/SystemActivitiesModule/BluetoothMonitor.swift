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
/// Starting it is what first touches Bluetooth, so the permission prompt belongs to `start`.
final class BluetoothMonitor: NSObject, BluetoothMonitoring {
    /// Earbuds often report their battery a moment after connecting.
    private static let batteryRetryDelay: Duration = .seconds(3)

    private let scheduler: any Scheduler
    private var onEvent: (@MainActor (BluetoothEvent) -> Void)?
    private var tracker = BluetoothConnectionTracker(connectedAtStart: [String]())
    private var batteryRetries: [String: ScheduledAction] = [:]
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    isolated deinit { stop() }

    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        // Devices connected before start are not announced, but their disconnect still is.
        let connected = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }.filter { $0.isConnected() }
        tracker = BluetoothConnectionTracker(connectedAtStart: connected.map(Self.key))
        connected.forEach(watchDisconnect)
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        batteryRetries.values.forEach { $0.cancel() }
        batteryRetries = [:]
        onEvent = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watchDisconnect(device)
        guard tracker.announcesConnection(of: Self.key(device)) else { return }
        let battery = BluetoothBattery.read(from: device)
        emit(device, connected: true, battery: battery)
        if battery == nil { retryBattery(of: device) }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        let key = Self.key(device)
        disconnectNotifications[key] = nil
        batteryRetries.removeValue(forKey: key)?.cancel()
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
        let key = Self.key(device)
        batteryRetries[key] = scheduler.schedule(after: Self.batteryRetryDelay) { [weak self] in
            guard let self else { return }
            batteryRetries[key] = nil
            guard let battery = BluetoothBattery.read(from: device), device.isConnected() else { return }
            emit(device, connected: true, battery: battery)
        }
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
