import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CalendarModule

@Suite struct RemindersAccessTests {
    let permissions = FakePermissionCenter()
    var access: RemindersAccess { RemindersAccess(permissions: permissions) }

    @Test func asksTheSystemWhileTheUserHasNotAnswered() async {
        permissions.statuses[.reminders] = .notDetermined
        let result = await access.request(openSettingsIfDenied: true)
        #expect(result == .granted)
        #expect(permissions.requested == [.reminders])
        #expect(permissions.openedSettings.isEmpty)
    }

    @Test func doesNothingWhenAccessIsAlreadyThere() async {
        permissions.statuses[.reminders] = .granted
        #expect(await access.request(openSettingsIfDenied: true) == .granted)
        #expect(permissions.requested.isEmpty)
    }

    @Test func aDeniedUserIsSentToSystemSettingsWhenAsked() async {
        permissions.statuses[.reminders] = .denied
        permissions.requestResult = .denied
        #expect(await access.request(openSettingsIfDenied: true) == .denied)
        #expect(permissions.requested == [.reminders])
        #expect(permissions.openedSettings == [.reminders])
    }

    @Test func aDeniedUserIsLeftAloneWhenNotAsked() async {
        permissions.statuses[.reminders] = .denied
        permissions.requestResult = .denied
        #expect(await access.request(openSettingsIfDenied: false) == .denied)
        #expect(permissions.openedSettings.isEmpty)
    }

    @Test func refusingTheFirstPromptDoesNotOpenSystemSettings() async {
        permissions.statuses[.reminders] = .notDetermined
        permissions.requestResult = .denied
        #expect(await access.request(openSettingsIfDenied: true) == .denied)
        #expect(permissions.openedSettings.isEmpty)
    }
}
