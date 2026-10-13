import Foundation
import IOBluetooth

/// Source of Bluetooth connect/disconnect events; faked in tests.
protocol BluetoothMonitoring: AnyObject {
    /// Calls `onEvent` when a device connects or disconnects, until `stop()`. Devices that are already
    /// connected are not reported.
    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void)
    func stop()
}

/// Watches IOBluetooth connect notifications and a disconnect notification per device.
/// Starting it is what first touches Bluetooth, so the permission prompt belongs to `start`.
final class BluetoothMonitor: NSObject, BluetoothMonitoring {
    private var onEvent: (@MainActor (BluetoothEvent) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) {
        stop()
        self.onEvent = onEvent
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        // Devices connected before start are not announced, but their disconnect still is.
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            watchDisconnect(device)
        }
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        onEvent = nil
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        watchDisconnect(device)
        emit(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotifications[device.addressString ?? ""] = nil
        emit(device, connected: false)
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        let key = device.addressString ?? ""
        guard disconnectNotifications[key] == nil,
              let notification = device.register(
                forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        else { return }
        disconnectNotifications[key] = notification
    }

    private func emit(_ device: IOBluetoothDevice, connected: Bool) {
        onEvent?(BluetoothEvent(
            name: device.name ?? device.addressString ?? "Bluetooth",
            kind: BluetoothDeviceKind(major: device.deviceClassMajor, minor: device.deviceClassMinor),
            connected: connected,
            battery: connected ? BluetoothBattery.read(from: device) : nil))
    }
}
