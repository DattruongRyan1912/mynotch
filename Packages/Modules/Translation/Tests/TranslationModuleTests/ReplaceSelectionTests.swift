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

    /// ⌃⌥T over a selection of `text`, translated. The selection is read when the tab opens, then again before the app is
    /// brought forward, before the write, and before a paste.
    func translateSelection(_ text: String = Self.text) async {
        await fixture.start()
        fixture.accessibility.selections = Array(repeating: text, count: 4)
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

    // MARK: Only the untouched selection

    @Test func editingTheInputDropsTheSource() async throws {
        await translateSelection()
        let translator = try #require(fixture.module.translator)
        translator.edit("Something completely different")
        #expect(fixture.state.selectionSource == nil)
        translator.translate()
        await fixture.translated()
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)
        #expect(fixture.accessibility.replacements.isEmpty)
    }

    @Test func returnOnEditedTextDropsTheSource() async throws {
        await translateSelection()
        let translator = try #require(fixture.module.translator)
        translator.submit("Good morning, my friend")
        #expect(fixture.state.selectionSource == nil)
        await fixture.translated()
        #expect(!fixture.state.showsReplace)
    }

    @Test func swappingTheDirectionDropsTheSource() async throws {
        await translateSelection()
        let translator = try #require(fixture.module.translator)
        translator.swap()
        // The translation became the text to translate back: it is no longer the selection.
        #expect(fixture.state.input == Self.translated)
        #expect(fixture.state.selectionSource == nil)
        await fixture.translated()
        #expect(!fixture.state.showsReplace)
        #expect(fixture.module.replaceSelection() == nil)
        #expect(fixture.accessibility.replacements.isEmpty)
    }

    @Test func theSameTextOrAnotherLanguageKeepsTheSource() async throws {
        await translateSelection()
        let translator = try #require(fixture.module.translator)
        // The field reporting the text it already shows, as an input method does while composing.
        translator.edit(Self.text)
        translator.submit(Self.text)
        #expect(fixture.state.selectionSource != nil)
        translator.setTarget(.ja)
        await fixture.translated()
        translator.setSource(.en)
        await fixture.translated()
        #expect(fixture.state.selectionSource == SelectionSource(text: Self.text, application: safari))
        #expect(fixture.state.canReplace)
        #expect(fixture.state.output == "\(Self.text) [en→ja]")
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
        var closesAtPaste = 0
        fixture.keystroke.onSend = {
            duringPaste = fixture.pasteboard.string(forType: .string)
            closesAtPaste = fixture.harness.presenter.closeCount
        }
        await fixture.module.replaceSelection()?.value
        #expect(fixture.keystroke.sent == 1)
        #expect(duringPaste == Self.translated)
        // The notch was already closed when ⌘V went out, so the keyboard was back in the app the text came from.
        #expect(closesAtPaste == 1)
        #expect(fixture.pasteboard.string(forType: .string) == "mine")
        #expect(fixture.state.selectionSource == nil)
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
    }

    @Test func aPasteThatCannotHaveTheKeyboardFailsAndShowsTheNotchAgain() async {
        await translateSelection()
        fillPasteboard()
        fixture.accessibility.replaces = false
        // Something else keeps the keyboard even after the notch closed.
        fixture.applications.holds = { true }
        await fixture.module.replaceSelection()?.value
        #expect(fixture.keystroke.sent == 0)
        #expect(fixture.pasteboard.string(forType: .string) == "mine")
        // Not a success: the notch comes back with the reason and the button to try again.
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(fixture.harness.presenter.openedTabs == ["translation", "translation"])
        #expect(fixture.state.replaceFailure == "Không thay được chữ ở app kia")
        #expect(fixture.state.selectionSource != nil)
        #expect(fixture.state.canReplace)
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
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
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

    @Test func aReplacementThatEndsAfterANewPressLeavesTheNewSelectionAlone() async {
        await translateSelection()
        fixture.accessibility.replaces = false
        fixture.handBackPauses.holds = true
        let old = fixture.module.replaceSelection()
        await eventually { fixture.handBackPauses.isWaiting }
        // The old replacement is waiting for the notch to hand the keyboard back when the shortcut is pressed again.
        // The reads so far: the tab's, before activating, before the write. Then the press, and the old one's last.
        fixture.accessibility.selections = [Self.text, Self.text, Self.text, "Good morning, my friend", "Good morning, my friend"]
        fixture.module.selectionShortcutPressed()
        await fixture.module.selectionRead?.value
        let fresh = fixture.state.selectionSource
        #expect(fresh?.text == "Good morning, my friend")
        let tabsOpened = fixture.harness.presenter.openedTabs.count

        fixture.handBackPauses.holds = false
        fixture.handBackPauses.release()
        await old?.value
        // What the old one found or did is not about the new selection: no message, no source dropped, no reopening.
        #expect(fixture.state.selectionSource == fresh)
        #expect(fixture.state.replaceFailure == nil)
        #expect(!fixture.state.isReplacing)
        #expect(fixture.harness.presenter.openedTabs.count == tabsOpened)
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
        // The one that handed the keyboard back before the stop; the stop closes nothing more.
        #expect(fixture.harness.presenter.closeCount == 1)
    }
}
