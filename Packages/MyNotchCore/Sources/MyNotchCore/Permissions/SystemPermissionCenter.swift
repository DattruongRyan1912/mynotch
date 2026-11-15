import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import EventKit

/// Real permission checks backed by the system frameworks. Only `request` prompts.
/// System audio and the folders have no status that can be read without prompting, so they stay `.unknown`.
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
            return Self.status(forBluetooth: CBManager.authorization)
        case .automation(let bundleID):
            return Self.automationStatus(bundleID: bundleID, askUserIfNeeded: false)
        case .microphone:
            return Self.status(forMicrophone: AVCaptureDevice.authorizationStatus(for: .audio))
        case .pasteboard:
            return Self.status(forPasteboard: NSPasteboard.general.accessBehavior)
        case .systemAudio, .downloadsFolder, .desktopFolder:
            return .unknown
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            // `kAXTrustedCheckOptionPrompt` is a mutable C global that Swift 6 rejects as not concurrency-safe;
            // the literal is its value. The user enables it in System Settings, so the status doesn't change right away.
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
        case .downloadsFolder:
            return await Self.listFolder(.downloadsDirectory)
        case .desktopFolder:
            return await Self.listFolder(.desktopDirectory)
        case .systemAudio, .pasteboard:
            // No API prompts for these: the user switches them on in System Settings.
            break
        }
        return status(of: permission)
    }

    public func openSystemSettings(for permission: Permission) {
        guard let url = URL(string: permission.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    public func recoverAccessibility() async -> PermissionStatus {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"
        _ = await AccessibilityRecovery.recover(bundleID: bundleID)
        return status(of: .accessibility)
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    nonisolated static func status(forBluetooth authorization: CBManagerAuthorization) -> PermissionStatus {
        switch authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    nonisolated static func status(forMicrophone authorization: AVAuthorizationStatus) -> PermissionStatus {
        switch authorization {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// `.default` and `.ask` both mean the system asks on programmatic access, so reading would not go through silently.
    nonisolated static func status(forPasteboard behavior: NSPasteboard.AccessBehavior) -> PermissionStatus {
        switch behavior {
        case .alwaysAllow: .granted
        case .alwaysDeny: .denied
        default: .notDetermined
        }
    }

    /// A target that is not running cannot be asked about, so that stays `.unknown` rather than "not asked".
    nonisolated static func status(forAutomation result: OSStatus) -> PermissionStatus {
        switch result {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
        default: .unknown
        }
    }

    nonisolated private static func automationStatus(bundleID: String, askUserIfNeeded: Bool) -> PermissionStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { pointer in
            AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded)
        return status(forAutomation: result)
    }

    /// Listing the folder is what makes macOS ask, and it waits for the answer, so it must not run on the main actor.
    private static func listFolder(_ directory: FileManager.SearchPathDirectory) async -> PermissionStatus {
        await Task.detached {
            guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first else { return .unknown }
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                return status(afterListing: nil)
            } catch {
                return status(afterListing: error)
            }
        }.value
    }

    /// Only a refusal is certain; any other failure (the folder moved, say) says nothing about the permission.
    nonisolated static func status(afterListing error: (any Error)?) -> PermissionStatus {
        guard let error else { return .granted }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError ? .denied : .unknown
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
