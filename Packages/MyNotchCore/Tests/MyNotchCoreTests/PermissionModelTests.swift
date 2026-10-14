import Testing
@testable import MyNotchCore

@Suite struct PermissionModelTests {
    nonisolated static let everyPermission: [Permission] = [
        .accessibility, .screenRecording, .calendars, .reminders, .bluetooth,
        .automation(bundleID: "com.spotify.client"), .microphone,
        .systemAudio, .downloadsFolder, .desktopFolder, .pasteboard,
    ]

    @Test(arguments: everyPermission)
    func everyPermissionHasANameAnIconAndAReason(permission: Permission) {
        #expect(!permission.displayName.isEmpty)
        #expect(!permission.systemImage.isEmpty)
        #expect(!permission.summary.isEmpty)
        #expect(!permission.instruction.isEmpty)
    }

    @Test(arguments: [
        (Permission.accessibility, "Trợ năng"),
        (.screenRecording, "Ghi màn hình"),
        (.calendars, "Lịch"),
        (.reminders, "Lời nhắc"),
        (.bluetooth, "Bluetooth"),
        (.automation(bundleID: "com.spotify.client"), "Điều khiển com.spotify.client"),
        (.microphone, "Micro"),
        (.systemAudio, "Ghi âm thanh hệ thống"),
        (.downloadsFolder, "Thư mục Downloads"),
        (.desktopFolder, "Thư mục Desktop"),
        (.pasteboard, "Dán từ app khác"),
    ])
    func namesAreVietnamese(permission: Permission, name: String) {
        #expect(permission.displayName == name)
    }

    @Test func theInstructionNamesTheListToSwitchOn() {
        #expect(Permission.accessibility.instruction == "Bật MyNotch trong danh sách Trợ năng (Accessibility) rồi quay lại.")
        #expect(Permission.screenRecording.instruction.contains("Screen & System Audio Recording"))
        #expect(Permission.downloadsFolder.instruction.contains("Files & Folders"))
        #expect(Permission.pasteboard.instruction.contains("Dán từ app khác (Paste from Other Apps)"))
    }

    @Test func theSystemAudioInstructionSaysWhatToDoWhenMyNotchIsNotListedYet() {
        let instruction = Permission.systemAudio.instruction
        #expect(instruction.contains("System Audio Recording Only"))
        #expect(instruction.contains("Chưa thấy MyNotch trong danh sách?"))
    }

    @Test(arguments: [
        (Permission.systemAudio, "Privacy_AudioCapture"),
        (.downloadsFolder, "Privacy_FilesAndFolders"),
        (.desktopFolder, "Privacy_FilesAndFolders"),
        (.pasteboard, "Privacy_Pasteboard"),
    ])
    func newPermissionsDeepLinkToTheirPanes(permission: Permission, anchor: String) {
        #expect(permission.settingsURL == "x-apple.systempreferences:com.apple.preference.security?" + anchor)
    }

    @Test func onlySystemAudioAndThePasteboardHaveNoRequest() {
        #expect(Permission.systemAudio.isPaneOnly)
        #expect(Permission.pasteboard.isPaneOnly)
        let others = Self.everyPermission.filter { $0 != .systemAudio && $0 != .pasteboard }
        #expect(!others.contains { $0.isPaneOnly })
    }

    @Test func missingMeansDeniedOrNeverAskedNotUnknown() {
        #expect(PermissionStatus.denied.isMissing)
        #expect(PermissionStatus.notDetermined.isMissing)
        #expect(!PermissionStatus.granted.isMissing)
        #expect(!PermissionStatus.unknown.isMissing)
    }

    @Test func promptablePermissionsRequestUntilTheUserHasAnswered() {
        for status in [PermissionStatus.notDetermined, .unknown] {
            #expect(Permission.calendars.grantAction(for: status) == .request)
            #expect(Permission.downloadsFolder.grantAction(for: status) == .request)
        }
        #expect(Permission.calendars.grantAction(for: .denied) == .openSettings)
        #expect(Permission.downloadsFolder.grantAction(for: .denied) == .openSettings)
    }

    @Test func settingsOnlyPermissionsAlwaysRequestFirst() {
        for status in [PermissionStatus.denied, .notDetermined, .unknown] {
            #expect(Permission.accessibility.grantAction(for: status) == .request)
            #expect(Permission.screenRecording.grantAction(for: status) == .request)
        }
    }

    @Test func panePermissionsOnlyOpenSettings() {
        for status in [PermissionStatus.denied, .notDetermined, .unknown] {
            #expect(Permission.systemAudio.grantAction(for: status) == .openSettings)
            #expect(Permission.pasteboard.grantAction(for: status) == .openSettings)
        }
    }
}
