import Foundation
import IOKit
import IOKit.pwr_mgt

/// Tells the helper when the Mac is about to sleep and when it has woken up: the firmware forgets a manual fan across sleep, so the
/// helper gives the fans back before it and again after it.
public final class PowerEvents: @unchecked Sendable {
    // iokit_common_msg(0x270), (0x280) and (0x300): the macros are not imported into Swift.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let queue: DispatchQueue
    private let onWillSleep: @Sendable () -> Void
    private let onDidWake: @Sendable () -> Void
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var port: IONotificationPortRef?

    public init(queue: DispatchQueue, onWillSleep: @escaping @Sendable () -> Void, onDidWake: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    /// Starts listening. Returns false when the system's power notifications cannot be had.
    @discardableResult
    public func start() -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &port, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            Unmanaged<PowerEvents>.fromOpaque(refcon).takeUnretainedValue().handle(messageType, messageArgument)
        }, &notifier)
        guard rootPort != 0, let port else { return false }
        IONotificationPortSetDispatchQueue(port, queue)
        return true
    }

    private func handle(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.systemWillSleep:
            onWillSleep()
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemHasPoweredOn:
            onDidWake()
        default:
            break
        }
    }
}
