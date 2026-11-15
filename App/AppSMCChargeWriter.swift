import BatteryModule
import FanHelperKit
import Foundation
import os
@preconcurrency import ServiceManagement

/// Bridges BatteryModule's hardware charge limiting commands to the privileged helper daemon
/// (`io.lucasvu.mynotch.fanhelper`) via secure XPC with asynchronous background serialization.
final class AppSMCChargeWriter: SMCChargeWriting, @unchecked Sendable {
    private let service = SMAppService.daemon(plistName: FanHelperIdentity.plistName)
    private let serialQueue = DispatchQueue(label: "io.lucasvu.mynotch.smc-writer", qos: .userInitiated)
    private let logger = Logger(subsystem: "io.lucasvu.mynotch", category: "battery")
    private let lock = NSLock()
    private var lastFailureDate: Date = .distantPast
    private let circuitCooldown: TimeInterval = 30.0
    private var inhibitUnsupportedUntil: Date = .distantPast
    private var _onInhibitStateChanged: (@Sendable (Bool) -> Void)?
    private var _onDischargeStateChanged: (@Sendable (Bool) -> Void)?

    var onInhibitStateChanged: (@Sendable (Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onInhibitStateChanged
        }
        set {
            lock.lock()
            _onInhibitStateChanged = newValue
            lock.unlock()
        }
    }

    var onDischargeStateChanged: (@Sendable (Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onDischargeStateChanged
        }
        set {
            lock.lock()
            _onDischargeStateChanged = newValue
            lock.unlock()
        }
    }

    private var isCircuitOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastFailureDate) < circuitCooldown
    }

    private func recordFailure() {
        lock.lock()
        lastFailureDate = Date()
        lock.unlock()
    }

    private func recordSuccess() {
        lock.lock()
        lastFailureDate = .distantPast
        lock.unlock()
    }

    var helperStatus: SMCHelperStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notInstalled
        @unknown default: return .notInstalled
        }
    }

    func registerHelper() throws {
        recordSuccess()
        try service.register()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func writeByte(key: String, value: UInt8) -> Bool {
        if key == BatteryChargeLimiter.chargeInhibitKey {
            return setChargeInhibit(inhibit: value != 0)
        } else if key == BatteryChargeLimiter.chargeLimitMaxKey {
            return setChargeLimit(limit: Int(value))
        } else if key == BatteryChargeLimiter.chargeDischargeKey {
            return setDischarge(discharge: value != 0)
        }
        return false
    }

    func setChargeInhibit(inhibit: Bool) -> Bool {
        guard helperStatus == .enabled else { return false }
        guard !isCircuitOpen else {
            logger.warning("Helper XPC circuit open (backoff active), skipping call")
            return false
        }
        if inhibit {
            lock.lock()
            let isUnsupported = Date() < inhibitUnsupportedUntil
            lock.unlock()
            if isUnsupported {
                logger.info("Charge inhibit is hardware-unsupported on this machine, skipping helper XPC call")
                return false
            }
        }
        dispatchHelperCall(name: "setChargeInhibit(\(inhibit))") { proxy, completion in
            proxy.setChargeInhibit(inhibit: inhibit) { [weak self] success in
                guard let self else {
                    completion(success)
                    return
                }
                if !success {
                    self.logger.warning("Helper setChargeInhibit(\(inhibit)) returned false from SMC layer")
                }
                completion(success)
            }
        }
        return true
    }

    func setChargeLimit(limit: Int) -> Bool {
        guard helperStatus == .enabled else { return false }
        guard !isCircuitOpen else {
            logger.warning("Helper XPC circuit open (backoff active), skipping call")
            return false
        }
        lock.lock()
        inhibitUnsupportedUntil = .distantPast
        lock.unlock()
        dispatchHelperCall(name: "setChargeLimit(\(limit))") { proxy, completion in
            proxy.setChargeLimit(limit: limit) { success in
                completion(success)
            }
        }
        return true
    }

    func setDischarge(discharge: Bool) -> Bool {
        guard helperStatus == .enabled else { return false }
        guard !isCircuitOpen else {
            logger.warning("Helper XPC circuit open (backoff active), skipping call")
            return false
        }
        dispatchHelperCall(name: "setDischarge(\(discharge))") { proxy, completion in
            proxy.setDischarge(discharge: discharge) { [weak self] success in
                if !success {
                    DispatchQueue.main.async {
                        self?.onDischargeStateChanged?(false)
                    }
                }
                completion(success)
            }
        }
        return true
    }

    private func dispatchHelperCall(
        name: String,
        _ body: @escaping @Sendable (any FanHelperProtocol, @escaping @Sendable (Bool) -> Void) -> Void
    ) {
        serialQueue.async { [weak self] in
            guard let self else { return }
            let connection = NSXPCConnection(machServiceName: FanHelperIdentity.machServiceName, options: .privileged)
            connection.remoteObjectInterface = FanHelperInterface.make()
            connection.setCodeSigningRequirement(FanHelperRequirement.helper)
            connection.resume()
            defer { connection.invalidate() }

            let semaphore = DispatchSemaphore(value: 0)

            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.logger.error("XPC error during \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self?.recordFailure()
                semaphore.signal()
            } as? any FanHelperProtocol

            guard let proxy else {
                self.logger.error("Failed to acquire FanHelperProtocol proxy for \(name, privacy: .public)")
                self.recordFailure()
                return
            }

            body(proxy) { [weak self] success in
                if success {
                    self?.logger.info("Successfully executed \(name, privacy: .public) via XPC")
                    self?.recordSuccess()
                } else {
                    self?.logger.warning("Helper returned false for \(name, privacy: .public)")
                }
                semaphore.signal()
            }

            // 6-second timeout allows launchd to cold-start helper if IdleExit(after: 20) previously exited
            let waitResult = semaphore.wait(timeout: .now() + .seconds(6))
            if waitResult == .timedOut {
                self.logger.error("Timeout (6s) waiting for helper XPC response on \(name, privacy: .public)")
                self.recordFailure()
            }
        }
    }
}
