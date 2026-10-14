import AppKit
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TranslationModule

@Suite struct ReplaceSelectionTests {
    static let text = "Hello, how are you today?"
    static let translated = "Hello, how are you today? [en→vi]"
    let fixture = ModuleFixture()
    let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")

    /// ⌃⌥T over a selection of `text`, translated. The selection is read twice: when the tab opens and when it is replaced.
    func translateSelection(_ text: String = Self.text) async {
        await fixture.start()
        fixture.accessibility.selections = [text, text]
        await fixture.pressShortcutAndRead()
        await fixture.translated()
    }

    func fillPasteboard() {
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("mine", forType: .string)
    }

    // MARK: When the button is there

    @Test func aSelectionFromAnotherAppCanBeReplaced() async {
        await translateSelection()
        #expect(fixture.state.selectionSource == SelectionSource(text: Self.text, application: safari))
        #expect(fixture.state.output == Self.translated)
        #expect(fixture.state.showsReplace)
        #expect(fixture.state.canReplace)

        await fixture.module.replaceSelection()?.value
        #expect(fixture.accessibility.replacements == [Self.translated])
        #expect(fixture.applications.activated == [safari])
        #expect(fixture.keystroke.sent == 0)
        #expect(!fixture.state.isReplacing)
        // Done: nothing left to replace, and the notch gets out of the way.
        #expect(fixture.state.selectionSource == nil)
        #expect(!fixture.state.showsReplace)
        #expect(fixture.state.replaceFailure == nil)
        #expect(fixture.harness.presenter.closeCount == 1)
    }

    @Test func textFromServicesOrTypedHasNothingToReplace() async {
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: Self.text))
        await fixture.translated()
        #expect(fixture.state.selectionSource == nil)
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)

        fixture.module.translator?.edit("Good morning, my friend")
        fixture.module.translator?.translate()
        await fixture.translated()
        #expect(fixture.module.replaceSelection() == nil)
        #expect(fixture.accessibility.replacements.isEmpty)
    }

    @Test func aNewShortcutPressDropsTheOldSource() async {
        await translateSelection()
        #expect(fixture.state.selectionSource != nil)
        // Nothing is selected this time: the reads continue past the end of the list.
        fixture.accessibility.selections = [Self.text]
        await fixture.pressShortcutAndRead()
        #expect(fixture.state.selectionSource == nil)
        #expect(!fixture.state.showsReplace)
    }

    @Test func aNewPressSweepsAwayTheOldMessageAndHint() async {
        await translateSelection()
        fixture.applications.exists = false
        await fixture.module.replaceSelection()?.value
        fixture.accessibility.isTrusted = false
        fixture.module.refreshAccessibility()
        #expect(fixture.state.replaceFailure != nil)
        #expect(fixture.state.needsAccessibility)

        fixture.accessibility.isTrusted = true
        fixture.accessibility.selections = [Self.text]
        await fixture.pressShortcutAndRead()
        #expect(fixture.state.replaceFailure == nil)
        #expect(!fixture.state.needsAccessibility)
    }

    @Test func servicesTextDropsTheOldSource() async {
        await translateSelection()
        #expect(fixture.state.selectionSource != nil)
        #expect(fixture.harness.services.handle(name: "translate", text: "Good morning, my friend"))
        #expect(fixture.state.selectionSource == nil)
    }

    @Test func typingWhileTheSelectionIsReadLeavesNothingToReplace() async {
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello"]
        fixture.pauses.holds = true
        fixture.module.selectionShortcutPressed()
        await eventually { fixture.pauses.isWaiting }
        fixture.module.translator?.edit("Typed meanwhile")
        fixture.pauses.release()
        await fixture.module.selectionRead?.value
        #expect(fixture.state.selectionSource == nil)
    }

    @Test func theButtonWaitsForAResultThatIsShown() async {
        await fixture.start()
        fixture.engine.holds = true
        fixture.accessibility.selections = [Self.text, Self.text]
        fixture.module.selectionShortcutPressed()
        await fixture.module.selectionRead?.value
        await eventually { fixture.engine.waiting }
        // Read, but not translated yet.
        #expect(fixture.state.selectionSource != nil)
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)
        fixture.engine.release()
        await fixture.translated()
        #expect(fixture.state.showsReplace)

        // While translating again, the old result is not what the button would write.
        fixture.engine.holds = true
        fixture.module.translator?.translate()
        await eventually { fixture.engine.waiting }
        #expect(fixture.state.isTranslating)
        #expect(!fixture.state.canReplace)
        #expect(fixture.module.replaceSelection() == nil)
        fixture.engine.release()
        await fixture.translated()
        #expect(fixture.state.canReplace)
    }

    @Test func aTranslationThatFailedHasNothingToReplaceWith() async {
        await fixture.start()
        fixture.engine.failure = .notInstalled
        fixture.accessibility.selections = [Self.text]
        await fixture.pressShortcutAndRead()
        await fixture.translated()
        #expect(fixture.state.banner != nil)
        #expect(!fixture.state.showsReplace)

        fixture.engine.failure = .failed("Không dịch được")
        fixture.module.translator?.translate()
        await fixture.translated()
        #expect(fixture.state.error != nil)
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)
    }

    // MARK: The setting

    @Test func theButtonIsOnByDefaultAndTheSettingTurnsItOff() async {
        #expect(fixture.keys.showReplaceButton.defaultValue)
        await translateSelection()
        await eventually { fixture.state.offersReplace }
        #expect(fixture.state.showsReplace)

        fixture.set(false, for: \.showReplaceButton)
        await eventually { !fixture.state.offersReplace }
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)

        fixture.set(true, for: \.showReplaceButton)
        await eventually { fixture.state.offersReplace }
        #expect(fixture.state.showsReplace)
    }

    @Test func aSettingTurnedOffBeforeStartingIsHonoured() async {
        fixture.set(false, for: \.showReplaceButton)
        await translateSelection()
        #expect(!fixture.state.showsReplace)
    }

    // MARK: Accessibility

    @Test func withoutAccessibilityTheButtonGivesWayToTheHint() async {
        await translateSelection()
        fixture.module.refreshAccessibility()
        #expect(!fixture.state.needsAccessibility)

        fixture.accessibility.isTrusted = false
        fixture.module.refreshAccessibility()
        #expect(fixture.state.needsAccessibility)
        #expect(!fixture.state.canReplace)
        #expect(fixture.module.replaceSelection() == nil)

        // Granted in System Settings: the next check takes the hint away.
        fixture.accessibility.isTrusted = true
        fixture.module.refreshAccessibility()
        #expect(!fixture.state.needsAccessibility)
        #expect(fixture.state.canReplace)
    }

    @Test func theHintIsOnlyForAResultThatCouldBeReplaced() async {
        await fixture.start()
        fixture.accessibility.isTrusted = false
        fixture.module.refreshAccessibility()
        #expect(!fixture.state.needsAccessibility)
    }

    @Test func permissionRevokedJustBeforeTheClickShowsTheHint() async {
        await translateSelection()
        fixture.accessibility.isTrusted = false
        await fixture.module.replaceSelection()?.value
        #expect(fixture.state.needsAccessibility)
        #expect(fixture.state.selectionSource != nil)
        #expect(fixture.accessibility.replacements.isEmpty)
        #expect(fixture.applications.activated.isEmpty)
        #expect(fixture.harness.presenter.closeCount == 0)
        #expect(!fixture.state.isReplacing)
    }

    @Test func theHintAsksThenOpensTheAccessibilityPane() async {
        await translateSelection()
        fixture.harness.permissions.requestResult = .denied
        await fixture.module.requestAccessibility()?.value
        #expect(fixture.harness.permissions.requested == [.accessibility])
        #expect(fixture.harness.permissions.openedSettings == [.accessibility])
    }

    @Test func aGrantFromThePromptNeedsNoSettingsPane() async {
        await translateSelection()
        fixture.harness.permissions.requestResult = .granted
        await fixture.module.requestAccessibility()?.value
        #expect(fixture.harness.permissions.requested == [.accessibility])
        #expect(fixture.harness.permissions.openedSettings.isEmpty)
    }

    @Test func askingForAccessibilityNeedsARunningModule() {
        #expect(fixture.module.requestAccessibility() == nil)
    }

    // MARK: Fallback and failure

    @Test func fallsBackToPastingAndTheClipboardComesBack() async {
        await translateSelection()
        fillPasteboard()
        fixture.accessibility.replaces = false
        var duringPaste: String?
        fixture.keystroke.onSend = { duringPaste = fixture.pasteboard.string(forType: .string) }
        await fixture.module.replaceSelection()?.value
        #expect(fixture.keystroke.sent == 1)
        #expect(duringPaste == Self.translated)
        #expect(fixture.pasteboard.string(forType: .string) == "mine")
        #expect(fixture.state.selectionSource == nil)
        #expect(fixture.harness.presenter.closeCount == 1)
    }

    @Test func aSelectionThatChangedIsKeptAndExplained() async {
        await translateSelection()
        // The first read was the tab's; the replacement looks at the second.
        fixture.accessibility.selections = [Self.text, "Something else"]
        await fixture.module.replaceSelection()?.value
        #expect(fixture.state.replaceFailure == "Vùng chọn đã đổi, nên chưa thay được")
        #expect(fixture.state.selectionSource != nil)
        #expect(fixture.accessibility.replacements.isEmpty)
        #expect(fixture.harness.presenter.closeCount == 0)
        #expect(!fixture.state.isReplacing)
    }

    @Test func aFailureIsExplainedAndTheTabStaysOpenToTryAgain() async {
        await translateSelection()
        fixture.applications.exists = false
        await fixture.module.replaceSelection()?.value
        #expect(fixture.state.replaceFailure == "Không thay được chữ ở app kia")
        #expect(fixture.state.selectionSource != nil)
        #expect(fixture.state.canReplace)
        #expect(fixture.harness.presenter.closeCount == 0)

        // A new translation sweeps the message away.
        fixture.module.translator?.translate()
        await fixture.translated()
        #expect(fixture.state.replaceFailure == nil)
    }

    @Test func aSecondClickWhileReplacingDoesNothing() async {
        await translateSelection()
        fixture.accessibility.replaces = false
        fixture.replacePauses.holds = true
        let first = fixture.module.replaceSelection()
        #expect(fixture.state.isReplacing)
        #expect(!fixture.state.canReplace)
        #expect(fixture.module.replaceSelection() == nil)
        await eventually { fixture.replacePauses.isWaiting }
        fixture.replacePauses.release()
        await first?.value
        #expect(fixture.keystroke.sent == 1)
    }

    // MARK: Stopping

    @Test func stoppingDropsTheSourceAndTheMessages() async {
        await translateSelection()
        fixture.accessibility.isTrusted = false
        fixture.module.refreshAccessibility()
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(fixture.state.selectionSource == nil)
        #expect(!fixture.state.needsAccessibility)
        #expect(!fixture.state.isReplacing)
        #expect(fixture.state.replaceFailure == nil)
        #expect(fixture.module.replaceSelection() == nil)
    }

    @Test func stoppingWhilePastingStillPutsTheClipboardBack() async {
        await translateSelection()
        fillPasteboard()
        fixture.accessibility.replaces = false
        fixture.replacePauses.holds = true
        let replacement = fixture.module.replaceSelection()
        await eventually { fixture.replacePauses.isWaiting }
        #expect(fixture.keystroke.sent == 1)

        let registry = fixture.harness.registry
        let stopping = Task { await registry.setEnabled(false, for: "translation") }
        await settle()
        // The app may not have read the pasteboard yet: the stop waits for the restore instead of cutting it short.
        #expect(fixture.pasteboard.string(forType: .string) == Self.translated)
        fixture.replacePauses.release()
        await stopping.value
        await replacement?.value
        #expect(fixture.pasteboard.string(forType: .string) == "mine")
        #expect(fixture.state.selectionSource == nil)
        #expect(fixture.harness.presenter.closeCount == 0)
    }
}
