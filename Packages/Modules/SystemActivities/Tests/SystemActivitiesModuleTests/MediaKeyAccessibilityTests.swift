import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

/// The hint in Settings that the HUD needs Accessibility, and the button that asks for it.
@Suite struct MediaKeyAccessibilityTests {
    final class Wish { var wanted = true }

    let permissions = FakePermissionCenter()
    let wish = Wish()

    func hint() -> MediaKeyAccessibility {
        let wish = wish
        return MediaKeyAccessibility(permissions: permissions, isWanted: { wish.wanted })
    }

    @Test func textAndButtonSayWhatIsNeeded() {
        #expect(MediaKeyAccessibilityHint.text == "Cần quyền Accessibility")
        #expect(MediaKeyAccessibilityHint.buttonTitle == "Cấp quyền")
    }

    @Test func missingFromTheStartWhileTheHUDIsOnWithoutAccessibility() {
        #expect(hint().isMissing)
    }

    @Test func noHintWhenAccessibilityIsAllowed() {
        permissions.statuses[.accessibility] = .granted
        #expect(!hint().isMissing)
    }

    @Test func noHintWhileTheHUDIsOff() {
        wish.wanted = false
        #expect(!hint().isMissing)
    }

    @Test func theHintFollowsTheSettingAndThePermissionAtEveryCheck() {
        wish.wanted = false
        let hint = hint()
        #expect(!hint.isMissing)

        wish.wanted = true
        // Nothing changes until the next check: the Settings row checks every 2 s while it is shown.
        #expect(!hint.isMissing)
        hint.refresh()
        #expect(hint.isMissing)

        permissions.statuses[.accessibility] = .granted
        hint.refresh()
        #expect(!hint.isMissing)

        permissions.statuses[.accessibility] = .denied
        hint.refresh()
        #expect(hint.isMissing)
    }

    @Test func theGrantButtonPromptsAndThenOpensTheAccessibilityPane() async {
        permissions.requestResult = .denied
        let hint = hint()

        await hint.grant()

        #expect(permissions.requested == [.accessibility])
        #expect(permissions.openedSettings == [.accessibility])
        #expect(hint.isMissing)
    }

    @Test func theGrantButtonLeavesSettingsClosedWhenThePromptAlreadyAllowedIt() async {
        permissions.requestResult = .granted
        let hint = hint()
        #expect(hint.isMissing)

        await hint.grant()

        #expect(permissions.requested == [.accessibility])
        #expect(permissions.openedSettings.isEmpty)
        #expect(!hint.isMissing)
    }

    @Test func checkingNeverPromptsOrOpensSettings() {
        let hint = hint()
        hint.refresh()
        #expect(permissions.requested.isEmpty)
        #expect(permissions.openedSettings.isEmpty)
    }
}
