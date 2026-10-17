import Dispatch
import Foundation
import IOBluetooth
import MyNotchTestSupport
import Synchronization
import Testing
@testable import SystemActivitiesModule

/// IOBluetooth calls the monitor back on a queue of its own (`com.apple.bluetooth.iobluetooth.coordinatorQueue`), and a
/// callback that is main-actor isolated traps there. These tests call the registered selectors through the Objective-C
/// runtime from another queue, as IOBluetooth does, with a stand-in for the device, so no Bluetooth is touched.
@Suite struct BluetoothMonitorCallbackTests {
    private let connect = #selector(BluetoothMonitor.deviceConnected(_:device:))
    private let disconnect = #selector(BluetoothMonitor.deviceDisconnected(_:device:))
    private let monitor = BluetoothMonitor(scheduler: ManualScheduler())

    /// Runs `calls` on a queue that is not the main one, and returns once the main queue has handled whatever they handed over.
    private func callFromAnotherQueue(_ calls: @escaping @Sendable (BluetoothMonitor) -> Void) async {
        let monitor = monitor
        await withCheckedContinuation { done in
            DispatchQueue(label: "MyNotchTests.iobluetooth.coordinatorQueue").async {
                calls(monitor)
                DispatchQueue.main.async { done.resume() }
            }
        }
    }

    /// Calls from another queue and waits for it with the main thread, so what the call handed to the main queue has not run
    /// yet when this returns: the main queue only gets to it after the caller's next lines.
    private func callWhileTheMainQueueIsHeldUp(_ call: @escaping @Sendable (BluetoothMonitor) -> Void) {
        let monitor = monitor
        let handedOver = DispatchSemaphore(value: 0)
        DispatchQueue(label: "MyNotchTests.iobluetooth.coordinatorQueue").async {
            call(monitor)
            handedOver.signal()
        }
        handedOver.wait()
    }

    @Test func aConnectCallbackFromAnotherQueueReachesTheHandlerOnTheMainThread() async {
        var events: [BluetoothEvent] = []
        var threads: [Bool] = []
        monitor.listen {
            events.append($0)
            threads.append(Thread.isMainThread)
        }
        let (connect, device) = (connect, FakeBluetoothDevice(name: "Magic Keyboard", address: "aa-bb", major: 5, minor: 0x10, battery: 80))
        await callFromAnotherQueue { _ = $0.perform(connect, with: NSObject(), with: device) }
        #expect(events == [BluetoothEvent(name: "Magic Keyboard", kind: .keyboard, connected: true, battery: .single(80))])
        #expect(threads == [true])
    }

    @Test func theDeviceIsOnlyWatchedForItsDisconnectOnTheMainThread() async {
        monitor.listen { _ in }
        let (connect, device) = (connect, FakeBluetoothDevice(name: "Mouse", address: "aa-bb", major: 5, minor: 0x20, battery: 50))
        await callFromAnotherQueue { _ = $0.perform(connect, with: NSObject(), with: device) }
        #expect(device.watchCalls == [true])
    }

    @Test func aDisconnectRightAfterAConnectArrivesInThatOrder() async {
        var events: [BluetoothEvent] = []
        monitor.listen { events.append($0) }
        let (connect, disconnect) = (connect, disconnect)
        let device = FakeBluetoothDevice(name: "AirPods", address: "cc-dd", major: 4, minor: 6, battery: 60)
        await callFromAnotherQueue {
            _ = $0.perform(connect, with: NSObject(), with: device)
            _ = $0.perform(disconnect, with: NSObject(), with: device)
        }
        #expect(events.map(\.connected) == [true, false])
        #expect(events.map(\.name) == ["AirPods", "AirPods"])
        #expect(events.map(\.kind) == [.headphones, .headphones])
    }

    @Test func aDeviceWithoutANameIsNamedByItsAddress() async {
        var events: [BluetoothEvent] = []
        monitor.listen { events.append($0) }
        let (connect, device) = (connect, FakeBluetoothDevice(name: nil, address: "ee-ff", major: 0, minor: 0, battery: 0))
        await callFromAnotherQueue { _ = $0.perform(connect, with: NSObject(), with: device) }
        #expect(events.map(\.name) == ["ee-ff"])
        #expect(events.map(\.battery) == [nil])
    }

    @Test func callbacksThatArriveAfterStopAreIgnored() async {
        var events: [BluetoothEvent] = []
        monitor.listen { events.append($0) }
        monitor.stop()
        let (connect, disconnect) = (connect, disconnect)
        let device = FakeBluetoothDevice(name: "Mouse", address: "aa-bb", major: 5, minor: 0x20, battery: 50)
        await callFromAnotherQueue {
            _ = $0.perform(connect, with: NSObject(), with: device)
            _ = $0.perform(disconnect, with: NSObject(), with: device)
        }
        #expect(events.isEmpty)
        #expect(device.watchCalls.isEmpty)
    }

    @Test func aCallbackThatIsStillOnItsWayWhenTheMonitorStopsIsIgnored() async {
        var events: [BluetoothEvent] = []
        monitor.listen { events.append($0) }
        let device = FakeBluetoothDevice(name: "Mouse", address: "aa-bb", major: 5, minor: 0x20, battery: 50)
        let connect = connect
        callWhileTheMainQueueIsHeldUp { _ = $0.perform(connect, with: NSObject(), with: device) }
        monitor.stop()
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(events.isEmpty)
        #expect(device.watchCalls.isEmpty)
    }
}

/// The protocol stands in for `IOBluetoothDevice` in the callbacks, so each selector it names must be one the real class
/// answers. Looks the class up without sending it a message, which would be the first touch of Bluetooth.
@Suite struct BluetoothDeviceSourceTests {
    @Test func namesOnlySelectorsIOBluetoothDeviceAnswers() throws {
        let device: AnyClass = try #require(NSClassFromString("IOBluetoothDevice"))
        var count: UInt32 = 0
        let descriptions = try #require(protocol_copyMethodDescriptionList(BluetoothDeviceSource.self, true, true, &count))
        defer { free(descriptions) }
        let selectors = (0..<Int(count)).compactMap { descriptions[$0].name }
        #expect(selectors.count == 6)
        for selector in selectors {
            #expect(class_getInstanceMethod(device, selector) != nil, "IOBluetoothDevice does not answer \(selector)")
        }
    }
}

/// Answers what `BluetoothMonitor` asks of an `IOBluetoothDevice`. Made on the callback queue, touched on the main thread
/// only through the monitor, like the real one.
private nonisolated final class FakeBluetoothDevice: NSObject, BluetoothDeviceSource, @unchecked Sendable {
    let name: String!
    let addressString: String!
    let deviceClassMajor: UInt32
    let deviceClassMinor: UInt32
    /// 0 means unknown, like the real getter.
    @objc let batteryPercentSingle: Int
    /// For each disconnect registration, whether it was made on the main thread.
    private let watches = Mutex<[Bool]>([])

    var watchCalls: [Bool] { watches.withLock { $0 } }

    init(name: String?, address: String, major: UInt32, minor: UInt32, battery: Int) {
        (self.name, addressString, deviceClassMajor, deviceClassMinor, batteryPercentSingle) = (name, address, major, minor, battery)
    }

    func isConnected() -> Bool { true }

    func register(forDisconnectNotification observer: Any!, selector inSelector: Selector!) -> IOBluetoothUserNotification! {
        watches.withLock { $0.append(Thread.isMainThread) }
        return nil
    }
}
