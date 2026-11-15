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

/// What the monitor uses of an `IOBluetoothDevice`. An Objective-C protocol so that the callbacks IOBluetooth makes can take
/// it, which lets tests stand in for the device without touching Bluetooth.
@objc nonisolated protocol BluetoothDeviceSource {
    var name: String! { get }
    var addressString: String! { get }
    var deviceClassMajor: UInt32 { get }
    var deviceClassMinor: UInt32 { get }
    func isConnected() -> Bool
    func register(forDisconnectNotification observer: Any!, selector inSelector: Selector!) -> IOBluetoothUserNotification!
}

extension IOBluetoothDevice: nonisolated BluetoothDeviceSource {}

typealias BluetoothDeviceObject = NSObject & BluetoothDeviceSource

/// What a callback copies out of the device while it is still on the queue IOBluetooth called it on.
nonisolated struct BluetoothDeviceReading: Equatable, Sendable {
    var key: String
    var name: String
    var kind: BluetoothDeviceKind

    static func key(of device: some BluetoothDeviceSource) -> String { device.addressString ?? "" }

    init(_ device: some BluetoothDeviceSource) {
        key = Self.key(of: device)
        name = device.name ?? device.addressString ?? "Bluetooth"
        kind = BluetoothDeviceKind(major: device.deviceClassMajor, minor: device.deviceClassMinor)
    }
}

/// Carries a device from IOBluetooth's queue to the main actor, where the monitor uses it: to watch its disconnect and to
/// read its battery, the same calls it made before IOBluetooth began to call back off the main thread.
private nonisolated struct DeviceBox: @unchecked Sendable {
    let device: BluetoothDeviceObject
}

/// Watches IOBluetooth connect notifications and a disconnect notification per device.
/// Starting it is what first touches Bluetooth, so the permission prompt belongs to `start`. The first IOBluetooth
/// call blocks until the user answers it, so `start` makes that call off the main thread and registers afterwards.
/// IOBluetooth calls back on a queue of its own: the callbacks only read the device there and go on in the main queue.
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
        listen(onEvent)
        starting = Task { [weak self] in
            await Self.waitForAccessDecision()
            guard !Task.isCancelled else { return }
            self?.register()
        }
    }

    /// `start` without the Bluetooth part: events that the callbacks below receive go to `onEvent`. For tests.
    func listen(_ onEvent: @escaping @MainActor (BluetoothEvent) -> Void) {
        self.onEvent = onEvent
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
        tracker = BluetoothConnectionTracker(connectedAtStart: connected.map(BluetoothDeviceReading.key(of:)))
        connected.forEach { watchDisconnect(key: BluetoothDeviceReading.key(of: $0), device: $0) }
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

    /// IOBluetooth calls the next two on its own queue, not the main one, so they are not main-actor isolated: the runtime
    /// traps when an isolated method is entered from the wrong queue. The first argument is the notification, which the
    /// monitor keeps itself.
    @objc nonisolated func deviceConnected(_ notification: NSObject, device: BluetoothDeviceObject) {
        handOver(device, connected: true)
    }

    @objc nonisolated func deviceDisconnected(_ notification: NSObject, device: BluetoothDeviceObject) {
        handOver(device, connected: false)
    }

    /// Reads what the event needs from the device here, then goes on in the main queue, which keeps the order the callbacks came in.
    private nonisolated func handOver(_ device: BluetoothDeviceObject, connected: Bool) {
        let reading = BluetoothDeviceReading(device)
        let box = DeviceBox(device: device)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.receive(reading, device: box.device, connected: connected) }
        }
    }

    /// A callback that was on its way when `stop()` ran finds `onEvent` gone and is dropped.
    private func receive(_ reading: BluetoothDeviceReading, device: BluetoothDeviceObject, connected: Bool) {
        guard onEvent != nil else { return }
        if connected {
            didConnect(reading, device)
        } else {
            didDisconnect(reading)
        }
    }

    private func didConnect(_ reading: BluetoothDeviceReading, _ device: BluetoothDeviceObject) {
        watchDisconnect(key: reading.key, device: device)
        guard tracker.connected(reading.key) else { return }
        let battery = BluetoothBattery.read(from: device)
        emit(reading, connected: true, battery: battery)
        if battery == nil { retryBattery(reading, of: device) }
    }

    private func didDisconnect(_ reading: BluetoothDeviceReading) {
        disconnectNotifications.removeValue(forKey: reading.key)?.unregister()
        batteryRetry.cancel(key: reading.key)
        tracker.disconnected(reading.key)
        emit(reading, connected: false, battery: nil)
    }

    private func watchDisconnect(key: String, device: BluetoothDeviceObject) {
        guard disconnectNotifications[key] == nil,
              let notification = device.register(
                forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        else { return }
        disconnectNotifications[key] = notification
    }

    private func retryBattery(_ reading: BluetoothDeviceReading, of device: BluetoothDeviceObject) {
        batteryRetry.start(
            key: reading.key,
            read: { device.isConnected() ? BluetoothBattery.read(from: device) : nil },
            deliver: { [weak self] in self?.emit(reading, connected: true, battery: $0) })
    }

    private func emit(_ reading: BluetoothDeviceReading, connected: Bool, battery: BluetoothBattery?) {
        onEvent?(BluetoothEvent(name: reading.name, kind: reading.kind, connected: connected, battery: battery))
    }
}
