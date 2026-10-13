import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import EventKit

/// Real permission checks backed by the system frameworks. Only `request` prompts.
public final class SystemPermissionCenter: PermissionCenter {
    public init() {}

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .calendars:
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return Self.map(EKEventStore.authorizationStatus(for: .reminder))
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .automation(let bundleID):
            return Self.automationStatus(bundleID: bundleID, askUserIfNeeded: false)
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            // The user enables it in System Settings, so the prompt never changes the status right away.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .calendars:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders:
            _ = try? await EKEventStore().requestFullAccessToReminders()
        case .bluetooth:
            await BluetoothAuthorizationRequest().run()
        case .automation(let bundleID):
            // Blocks until the user answers, so it must not run on the main actor.
            return await Task.detached { Self.automationStatus(bundleID: bundleID, askUserIfNeeded: true) }.value
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return status(of: permission)
    }

    public func openSystemSettings(for permission: Permission) {
        guard let url = URL(string: permission.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    nonisolated private static func automationStatus(bundleID: String, askUserIfNeeded: Bool) -> PermissionStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { pointer in
            AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &target)
        }
        guard created == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined   // not running yet, or consent not requested
        }
    }
}

/// Creating a central manager shows the Bluetooth prompt; its first state update means the user has answered.
private final class BluetoothAuthorizationRequest: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Keeps the manager alive until that first update, then releases it.
    func run() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager = CBCentralManager(delegate: self, queue: nil)
        }
        manager = nil
    }

    /// `queue: nil` delivers delegate calls on the main queue.
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            continuation?.resume()
            continuation = nil
        }
    }
}
