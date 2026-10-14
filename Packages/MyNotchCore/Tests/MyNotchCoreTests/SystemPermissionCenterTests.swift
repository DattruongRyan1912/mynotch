import AppKit
import AVFoundation
import CoreBluetooth
import Foundation
import Testing
@testable import MyNotchCore

/// Only the mapping from system answers to `PermissionStatus` and what needs no system call: nothing here asks the
/// system, so no prompt can appear.
@Suite struct SystemPermissionCenterTests {
    @Test func systemAudioAndFoldersAreUnknownBecauseMacOSOnlyAnswersByPrompting() {
        let center = SystemPermissionCenter()
        #expect(center.status(of: .systemAudio) == .unknown)
        #expect(center.status(of: .downloadsFolder) == .unknown)
        #expect(center.status(of: .desktopFolder) == .unknown)
    }

    @Test func requestingSystemAudioOnlyReportsTheStatus() async {
        #expect(await SystemPermissionCenter().request(.systemAudio) == .unknown)
    }

    @Test(arguments: [
        (NSPasteboard.AccessBehavior.alwaysAllow, PermissionStatus.granted),
        (.alwaysDeny, .denied),
        (.ask, .notDetermined),
        (.default, .notDetermined),
    ])
    func pasteboardBehaviourMapsToStatus(behavior: NSPasteboard.AccessBehavior, status: PermissionStatus) {
        #expect(SystemPermissionCenter.status(forPasteboard: behavior) == status)
    }

    @Test(arguments: [
        (CBManagerAuthorization.allowedAlways, PermissionStatus.granted),
        (.notDetermined, .notDetermined),
        (.denied, .denied),
        (.restricted, .denied),
    ])
    func bluetoothAuthorizationMapsToStatus(authorization: CBManagerAuthorization, status: PermissionStatus) {
        #expect(SystemPermissionCenter.status(forBluetooth: authorization) == status)
    }

    @Test(arguments: [
        (AVAuthorizationStatus.authorized, PermissionStatus.granted),
        (.notDetermined, .notDetermined),
        (.denied, .denied),
        (.restricted, .denied),
    ])
    func microphoneAuthorizationMapsToStatus(authorization: AVAuthorizationStatus, status: PermissionStatus) {
        #expect(SystemPermissionCenter.status(forMicrophone: authorization) == status)
    }

    @Test(arguments: [
        (OSStatus(noErr), PermissionStatus.granted),
        (OSStatus(errAEEventNotPermitted), .denied),
        (OSStatus(errAEEventWouldRequireUserConsent), .notDetermined),
        (OSStatus(procNotFound), .unknown),
        (OSStatus(-1), .unknown),
    ])
    func automationResultMapsToStatus(result: OSStatus, status: PermissionStatus) {
        #expect(SystemPermissionCenter.status(forAutomation: result) == status)
    }

    @Test func listingAFolderIsGrantedUnlessTheSystemRefusesIt() {
        #expect(SystemPermissionCenter.status(afterListing: nil) == .granted)
        let refused = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        #expect(SystemPermissionCenter.status(afterListing: refused) == .denied)
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(SystemPermissionCenter.status(afterListing: missing) == .unknown)
    }
}
