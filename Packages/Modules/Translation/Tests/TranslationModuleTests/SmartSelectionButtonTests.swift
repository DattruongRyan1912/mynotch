import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// The small translate button: for a selection that was read but not translated by itself, for a reason that is only a guess.
/// Everything here runs on fakes: the input, the Accessibility reads, the window, the pointer and the clock.
@Suite struct SmartSelectionButtonTests {
    let fixture = ModuleFixture()
    let heading = "PageSpeed Insights"
    let english = "The quick brown fox jumps over the lazy dog"

    var chip: FakeChipWindow { fixture.chipWindow }
    var log: FakeSelectionLog { fixture.selectionLog }
    var settings: ModuleSettings { fixture.harness.settingsEnvironment(for: "translation")!.settings }
    var buttonLines: [String] { log.lines(startingWith: "button ") }

    /// The delay passes: the time between the decision and the button being on screen.
    func letItAppear() {
        fixture.harness.scheduler.advance(by: .milliseconds(300))
    }

    func select(_ text: String?) async {
        await fixture.dragSelecting(text)
        letItAppear()
    }

    /// The selection ends in no new button, however long one waits.
    func expectNoButton(_ text: String?, because reason: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) async {
        let (shown, lines) = (chip.shown.count, buttonLines.count)
        await fixture.dragSelecting(text)
        fixture.harness.scheduler.advance(by: .seconds(10))
        #expect(chip.shown.count == shown, "\(String(describing: text))", sourceLocation: sourceLocation)
        #expect(buttonLines.count == lines, sourceLocation: sourceLocation)
        if let reason { #expect(log.contains("skip reason=\(reason)"), sourceLocation: sourceLocation) }
    }

    // MARK: which skips get it

    @Test(arguments: [
        ("PageSpeed Insights", "shape-name"),
        ("Getting Started", "shape-name"),
        ("Tim Cook", "shape-name"),
        ("Hello", "shape-name"),
        ("Hello world", "low-confidence"),
        ("ephemeral", "shape-short"),
        ("shape", "shape-short"),
        ("Hôm nay trời đẹp quá, chúng ta đi dạo nhé", "same-language"),
    ])
    func aSoftSkipGetsTheButton(text: String, reason: String) async throws {
        await fixture.start()
        await fixture.dragSelecting(text)
        #expect(log.contains("skip reason=\(reason)"))
        #expect(chip.current == nil, "not before its delay")
        letItAppear()
        let shown = try #require(chip.current)
        #expect(shown.content.kind == .translateButton)
        #expect(shown.content.text.isEmpty)
        #expect(buttonLines == ["button shown reason=\(reason)"])
    }

    @Test(arguments: [
        ("let value = compute(input)", "shape-code"),
        ("https://example.com/blog/2026/10/why-we-moved", "shape-code"),
        ("/Users/ryan/Project/MyNotch/Packages", "shape-code"),
        ("2026-10-15 09:12:44 INFO Server started on port 8080", "shape-code"),
        ("john.smith@example.com", "shape-code"),
        ("snake_case_name another_one", "shape-code"),
        ("안녕하세요 여러분 만나서 반갑습니다", "unsupported-language"),
    ])
    func aHardSkipGetsNothing(text: String, reason: String) async {
        await fixture.start()
        await expectNoButton(text, because: reason)
    }

    @Test func nothingSelectedGetsNothing() async {
        await fixture.start()
        await expectNoButton(nil, because: "none")
    }

    @Test func aPasswordFieldGetsNothing() async {
        await fixture.start()
        fixture.accessibility.isSecureField = true
        await expectNoButton(heading, because: "none")
    }

    @Test func secureInputGetsNothing() async {
        await fixture.start()
        fixture.accessibility.secureInputHolders = [42]
        await expectNoButton(heading, because: "secure")
    }

    @Test func blankTextGetsNothing() async {
        await fixture.start()
        await expectNoButton("   \n ", because: "blank")
    }

    @Test func tooMuchTextGetsNothing() async {
        await fixture.start()
        await expectNoButton(String(repeating: "Hello ", count: 400), because: "too-long")
    }

    @Test func myNotchItselfGetsNothing() async {
        await fixture.start()
        fixture.accessibility.application = FocusedApplication(processID: getpid(), bundleID: "io.lucasvu.mynotch")
        await expectNoButton(heading, because: "own-app")
    }

    @Test func anAppOnTheDenyListGetsNothing() async {
        fixture.set(["com.apple.Safari"], for: \.selectionDenyList)
        await fixture.start()
        await expectNoButton(heading, because: "denied")
    }

    @Test func withoutAccessibilityThereIsNothingToReadAndNoButton() async {
        fixture.accessibility.isTrusted = false
        await fixture.start()
        await expectNoButton(heading, because: "not-trusted")
    }

    @Test func anAppThatDoesNotAnswerGetsNothingThenNothingDuringItsCoolDown() async {
        await fixture.start()
        fixture.accessibility.hangs = true
        await expectNoButton(heading, because: "unresponsive")
        fixture.accessibility.hangs = false
        await expectNoButton(heading, because: "cooldown")
    }

    @Test func aPriceThatCannotBeConvertedGetsNothing() async {
        await fixture.start()
        fixture.set(true, for: \.convertCurrency)
        await expectNoButton("$12", because: "no-conversion")
    }

    @Test func aPreviewThatWasOnlySupersededGetsNothing() async {
        await fixture.start()
        fixture.previewEngine.failure = .cancelled
        await expectNoButton(english, because: "cancelled")
    }

    @Test func whatTheChipAlreadyUnderstandsGetsItsChipNotAButton() async throws {
        await fixture.start()
        await select("5 ft 11 in")
        #expect(try #require(chip.current).content.kind == .conversion)
        await select(english)
        #expect(try #require(chip.current).content.kind == .translation)
        #expect(buttonLines.isEmpty)
    }

    @Test func theSameSelectionAgainDoesNotBringTheButtonBackAfterItWent() async {
        await fixture.start()
        await select(heading)
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(!chip.isVisible)
        let shown = chip.shown.count
        await select(heading)
        #expect(chip.shown.count == shown)
        #expect(log.contains("skip reason=unchanged"))
    }

    @Test func aSecondDifferentSoftSelectionGetsItsOwnButton() async {
        await fixture.start()
        await select(heading)
        await select("Getting Started")
        #expect(buttonLines == ["button shown reason=shape-name", "button shown reason=shape-name"])
        #expect(chip.shown.count == 2)
    }

    // MARK: the setting

    @Test func withTheSettingOffThereIsNoButton() async {
        fixture.set(false, for: \.selectionButton)
        await fixture.start()
        await expectNoButton(heading, because: "shape-name")
    }

    @Test func turningTheSettingOffTakesTheButtonAway() async {
        await fixture.start()
        await select(heading)
        #expect(chip.isVisible)
        fixture.set(false, for: \.selectionButton)
        await select("Getting Started")
        #expect(!chip.isVisible)
    }

    @Test func theButtonDoesNotNeedTheResultChipToBeOn() async {
        fixture.set(false, for: \.selectionChip)
        await fixture.start()
        await select(heading)
        #expect(chip.current?.content.kind == .translateButton)
        // And a result still waits for its own setting.
        await select("5 ft 11 in")
        #expect(!chip.isVisible)
    }

    @Test func theButtonNeverMakesALiveActivity() async {
        fixture.set(true, for: \.selectionActivity)
        await fixture.start()
        await select(heading)
        #expect(chip.isVisible)
        #expect(fixture.harness.activities.entries.isEmpty)
        #expect(log.lines(startingWith: "activity ").isEmpty)
        #expect(log.lines(startingWith: "chip shown").isEmpty)
    }

    @Test func withTheSettingOffNothingIsEvenScheduled() async {
        fixture.set(false, for: \.selectionButton)
        await fixture.start()
        await fixture.dragSelecting(heading)
        #expect(fixture.harness.scheduler.pendingCount == 0)
        let second = ModuleFixture()
        await second.start()
        await second.dragSelecting(heading)
        #expect(second.harness.scheduler.pendingCount > 0, "the button waits for its delay")
    }

    @Test func turningTheSettingOffDuringTheDelayMeansItIsNeverShown() async {
        await fixture.start()
        await fixture.dragSelecting(heading)
        fixture.set(false, for: \.selectionButton)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty)
    }

    @Test func turningTheFeatureOffTakesTheButtonAway() async {
        await fixture.start()
        await select(heading)
        fixture.set(false, for: \.smartSelection)
        await eventually { !chip.isVisible }
        #expect(!chip.isVisible)
    }

    @Test func stoppingTheModuleTakesTheButtonAway() async {
        await fixture.start()
        await select(heading)
        await fixture.module.stop()
        #expect(!chip.isVisible)
    }

    // MARK: how long it takes to appear and how long it stays

    @Test func appearsThreeHundredMillisecondsAfterTheDecisionAndStaysFourSeconds() async {
        await fixture.start()
        await fixture.dragSelecting(heading)
        fixture.harness.scheduler.advance(by: .milliseconds(299))
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(chip.isVisible)
        fixture.harness.scheduler.advance(by: .milliseconds(3_999))
        #expect(chip.isVisible)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(!chip.isVisible)
    }

    @Test func aButtonUnderThePointerStaysUntilItLeavesAndTwoSecondsMore() async throws {
        await fixture.start()
        await select(heading)
        try #require(chip.current).content.hover(true)
        fixture.harness.scheduler.advance(by: .seconds(60))
        #expect(chip.isVisible)
        try #require(chip.current).content.hover(false)
        fixture.harness.scheduler.advance(by: .milliseconds(1_999))
        #expect(chip.isVisible)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(!chip.isVisible)
    }

    // MARK: what hides it

    enum Trigger: CaseIterable, CustomTestStringConvertible {
        case pressElsewhere, typing, escape, copy, anotherApp, newSelectionOfNothing, pointerFarAway

        var testDescription: String { String(describing: self) }
    }

    func fire(_ trigger: Trigger) async {
        switch trigger {
        case .pressElsewhere: fixture.input.send(.mouseDown(CGPoint(x: 600, y: 600)))
        case .typing: fixture.input.press(0)
        case .escape: fixture.input.press(53)
        case .copy: fixture.input.press(8, command: true)
        case .anotherApp: fixture.input.send(.applicationActivated(99))
        case .newSelectionOfNothing: await fixture.dragSelecting(nil)
        case .pointerFarAway:
            fixture.pointer.location = CGPoint(x: 900, y: 900)
            fixture.harness.scheduler.advance(by: SelectionChip.pointerPoll)
        }
    }

    @Test(arguments: Trigger.allCases)
    func theseTakeItAwayOnceItIsUp(trigger: Trigger) async {
        await fixture.start()
        await select(heading)
        #expect(chip.isVisible)
        await fire(trigger)
        #expect(!chip.isVisible)
        fixture.harness.scheduler.advance(by: .seconds(10))
        #expect(chip.shown.count == 1, "it does not come back")
    }

    @Test(arguments: Trigger.allCases)
    func theseMeanItIsNeverShownIfTheyComeDuringTheDelay(trigger: Trigger) async {
        await fixture.start()
        await fixture.dragSelecting(heading)
        await fire(trigger)
        fixture.harness.scheduler.advance(by: .seconds(10))
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty, "nothing was shown, so the log says nothing was")
    }

    // MARK: before the decision (the pause and the read, a quarter second or so)

    func dragAndThen(_ text: String, _ trigger: () -> Void) async {
        fixture.accessibility.standing = text
        fixture.input.drag(from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 500))
        trigger()
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        fixture.harness.scheduler.advance(by: .seconds(10))
    }

    @Test func aQuickDragAndCopyNeverShowsTheButton() async {
        await fixture.start()
        await dragAndThen(heading) { fixture.input.press(8, command: true) }
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty)
    }

    @Test func aResultChipStillComesUpAfterACopy() async throws {
        await fixture.start()
        await dragAndThen("5 ft 11 in") { fixture.input.press(8, command: true) }
        #expect(chip.shown.count == 1)
        #expect(try #require(chip.shown.first).content.kind == .conversion)
    }

    @Test(arguments: [Trigger.pressElsewhere, .typing, .escape])
    func theseBeforeTheDecisionMeanThereIsNoButton(trigger: Trigger) async {
        await fixture.start()
        await dragAndThen(heading) {
            switch trigger {
            case .pressElsewhere: fixture.input.send(.mouseDown(CGPoint(x: 600, y: 600)))
            case .typing: fixture.input.press(0)
            default: fixture.input.press(53)
            }
        }
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty)
    }

    @Test func aPointerThatLeftBeforeTheDecisionMeansThereIsNoButton() async {
        await fixture.start()
        await dragAndThen(heading) { fixture.pointer.location = CGPoint(x: 900, y: 900) }
        #expect(chip.shown.isEmpty)
        #expect(buttonLines.isEmpty)
        #expect(log.contains("skip reason=shape-name"), "it was read, and there was nothing to show")
    }

    @Test func aCopyIsForgottenByTheNextSelection() async {
        await fixture.start()
        await dragAndThen(heading) { fixture.input.press(8, command: true) }
        #expect(chip.shown.isEmpty)
        await select("Getting Started")
        #expect(chip.current?.content.kind == .translateButton)
    }

    @Test func aCopyIsForgottenByASelectionMadeWithTheKeyboard() async {
        await fixture.start()
        await dragAndThen(heading) { fixture.input.press(8, command: true) }
        fixture.accessibility.standing = "Getting Started"
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        letItAppear()
        #expect(chip.current?.content.kind == .translateButton)
    }

    @Test func copyingLeavesAResultChipAlone() async {
        await fixture.start()
        await select("5 ft 11 in")
        fixture.input.press(8, command: true)
        #expect(chip.isVisible)
    }

    @Test func aNewSelectionThatShowsAResultReplacesTheButton() async throws {
        await fixture.start()
        await select(heading)
        await select("5 ft 11 in")
        #expect(try #require(chip.current).content.kind == .conversion)
        fixture.harness.scheduler.advance(by: .seconds(10))
        #expect(!chip.isVisible)
    }

    @Test func aNewSelectionThatIsTheSameKindReplacesItAndRestartsTheClock() async {
        await fixture.start()
        await select(heading)
        fixture.harness.scheduler.advance(by: .seconds(3))
        await select("Getting Started")
        fixture.harness.scheduler.advance(by: .milliseconds(3_900))
        #expect(chip.isVisible)
        fixture.harness.scheduler.advance(by: .milliseconds(100))
        #expect(!chip.isVisible)
    }

    @Test func aResultChipGoesAtOnceWhenTheNextSelectionOnlyGetsAButton() async {
        await fixture.start()
        await select("5 ft 11 in")
        await fixture.dragSelecting(heading)
        #expect(!chip.isVisible, "the old result is about a selection that is gone")
        letItAppear()
        #expect(chip.current?.content.kind == .translateButton)
    }

    @Test func aKeyboardSelectionsButtonStaysEvenThoughThePointerIsFarAway() async {
        await fixture.start()
        fixture.accessibility.standing = heading
        fixture.accessibility.bounds = CGRect(x: 800, y: 100, width: 200, height: 20)
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        letItAppear()
        #expect(chip.isVisible)
        fixture.pointer.location = CGPoint(x: 5, y: 5)
        fixture.harness.scheduler.advance(by: .seconds(3))
        #expect(chip.isVisible)
    }

    @Test func aKeyboardSelectionsButtonIsNotTakenAwayByThePointerEvenWhenItWasNear() async {
        await fixture.start()
        fixture.accessibility.standing = heading
        // The selection is right where the pointer is, but the keyboard made it.
        fixture.accessibility.bounds = CGRect(x: 100, y: 400, width: 200, height: 20)
        fixture.pointer.location = CGPoint(x: 300, y: 490)
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        letItAppear()
        #expect(chip.isVisible)
        fixture.pointer.location = CGPoint(x: 1_300, y: 100)
        fixture.harness.scheduler.advance(by: .seconds(3))
        #expect(chip.isVisible)
    }

    // MARK: where it goes

    @Test func aMouseSelectionsButtonIsBelowWhereTheDragEnded() async throws {
        await fixture.start()
        fixture.accessibility.bounds = CGRect(x: 100, y: 100, width: 200, height: 20)
        fixture.pointer.location = CGPoint(x: 250, y: 790)
        await fixture.dragSelecting(heading, from: CGPoint(x: 100, y: 790), to: CGPoint(x: 250, y: 790))
        letItAppear()
        // 20 pt down from the top for Accessibility is 780 from the bottom for AppKit; the end is at the pointer.
        #expect(try #require(chip.current).anchor == CGRect(x: 250, y: 780, width: 0, height: 20))
    }

    @Test func aKeyboardSelectionsButtonIsBelowItsRightEdge() async throws {
        await fixture.start()
        fixture.accessibility.standing = heading
        fixture.accessibility.bounds = CGRect(x: 100, y: 100, width: 200, height: 20)
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        letItAppear()
        #expect(try #require(chip.current).anchor == CGRect(x: 300, y: 780, width: 0, height: 20))
    }

    @Test func withoutARectangleItIsWhereThePointerIs() async throws {
        await fixture.start()
        await select(heading)
        #expect(try #require(chip.current).anchor == CGRect(x: 300, y: 500, width: 0, height: 0))
    }

    // MARK: a click

    @Test func aClickOpensTheTabOnTheSelectionOnceAndTheButtonGoes() async throws {
        await fixture.start()
        await select(heading)
        let content = try #require(chip.current).content
        #expect(fixture.accessibility.reads == 1, "the passive read")
        content.open()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == heading)
        #expect(fixture.accessibility.reads == 1, "the selection the button was offered for is not read again")
        #expect(!chip.isVisible)
        #expect(log.lines.filter { $0 == "button clicked" }.count == 1)
        // The button is gone: a second click on it does nothing.
        content.open()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(log.lines.filter { $0 == "button clicked" }.count == 1)
    }

    /// Chrome and Electron apps (Claude, VS Code) move their focus off selected page text to the group around it, which has no
    /// selected text, so a read at the time of the click finds nothing; that used to open the tab empty.
    @Test func aClickOpensTheTextItWasOfferedForAfterTheAppStopsSayingIt() async throws {
        fixture.focus("com.anthropic.claudefordesktop")
        await fixture.start()
        await select(heading)
        fixture.accessibility.standing = nil
        fixture.accessibility.application = nil
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.state.input == heading)
        #expect(fixture.state.selectionSource?.text == heading)
        #expect(fixture.state.selectionSource?.application.bundleID == "com.anthropic.claudefordesktop")
    }

    @Test func aClickLeavesTheTabHoldingTheSelectionAndItsApp() async throws {
        await fixture.start()
        await select(heading)
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.state.selectionSource?.text == heading)
        #expect(fixture.state.selectionSource?.application.bundleID == "com.apple.Safari")
    }

    /// The button's click, whatever "Dịch ngay khi mở" says: the tab opens on the text and translates it at once.
    @Test(arguments: [true, false])
    func aClickAlwaysTranslatesWhatItOpens(autoTranslateOnOpen: Bool) async throws {
        fixture.set(autoTranslateOnOpen, for: \.autoTranslateOnOpen)
        await fixture.start()
        await select(heading)
        try #require(chip.current).content.open()
        await fixture.translated()
        await settle()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == heading)
        #expect(fixture.engine.requests.map(\.text) == [heading])
        #expect(!fixture.state.output.isEmpty)
    }

    /// ⌃⌥T itself is as it was: it translates when the setting says so and not otherwise.
    @Test func theShortcutStillOpensWithoutTranslatingWhenTheSettingIsOff() async {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        fixture.accessibility.standing = heading
        await fixture.pressShortcutAndRead()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == heading)
        fixture.harness.scheduler.advance(by: .seconds(1))
        await settle()
        #expect(fixture.module.translator?.translation == nil)
        #expect(fixture.engine.requests.isEmpty)
        #expect(fixture.state.output.isEmpty)
    }

    /// The registered hotkey itself, as the system calls it: it goes by the setting, not by the button's request.
    @Test(arguments: [true, false])
    func thePressedHotkeyGoesByTheSetting(autoTranslateOnOpen: Bool) async {
        fixture.set(autoTranslateOnOpen, for: \.autoTranslateOnOpen)
        await fixture.start()
        fixture.accessibility.standing = heading
        #expect(fixture.harness.hotkeyBackend.trigger("translation_translateSelection"))
        await fixture.module.selectionRead?.value
        fixture.harness.scheduler.advance(by: .seconds(1))
        await fixture.translated()
        await settle()
        #expect(fixture.state.input == heading)
        #expect(fixture.engine.requests.map(\.text) == (autoTranslateOnOpen ? [heading] : []))
    }

    @Test func theShortcutStillTranslatesWhenTheSettingIsOn() async {
        await fixture.start()
        fixture.accessibility.standing = heading
        await fixture.pressShortcutAndRead()
        await fixture.translated()
        await settle()
        #expect(fixture.engine.requests.map(\.text) == [heading])
    }

    /// Only the button's own request is at once: the next press of the shortcut goes by the setting again.
    @Test func aClickDoesNotChangeWhatTheNextShortcutPressDoes() async throws {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        await select(heading)
        try #require(chip.current).content.open()
        await fixture.translated()
        await settle()
        #expect(fixture.engine.requests.count == 1)
        fixture.accessibility.standing = "Getting Started"
        await fixture.pressShortcutAndRead()
        fixture.harness.scheduler.advance(by: .seconds(1))
        await settle()
        #expect(fixture.state.input == "Getting Started")
        #expect(fixture.engine.requests.count == 1, "it opened without translating")
        #expect(fixture.state.output.isEmpty)
    }

    @Test func aClickBeforeItsDelayCannotHappen() async throws {
        await fixture.start()
        await fixture.dragSelecting(heading)
        #expect(chip.current == nil)
        #expect(fixture.harness.presenter.openedTabs.isEmpty)
    }

    // MARK: suppression

    @Test func hidingTheAppFromTheChipsMenuAlsoSilencesTheButton() async throws {
        await fixture.start()
        await select("5 ft 11 in")
        let deny = try #require(chip.current?.content.deny)
        deny()
        #expect(settings.value(fixture.keys.selectionDenyList) == ["com.apple.Safari"])
        await expectNoButton(heading, because: "denied")
    }

    @Test func hidingTheAppFromTheButtonsOwnMenuTakesItAwayAndSilencesTheApp() async throws {
        await fixture.start()
        await select(heading)
        let deny = try #require(chip.current?.content.deny)
        deny()
        #expect(!chip.isVisible)
        #expect(settings.value(fixture.keys.selectionDenyList) == ["com.apple.Safari"])
        #expect(fixture.harness.presenter.toastCount == 1)
        await expectNoButton("Getting Started", because: "denied")
    }

    @Test func undoingBringsTheButtonBackForTheNextSelection() async throws {
        await fixture.start()
        await select(heading)
        let deny = try #require(chip.current?.content.deny)
        deny()
        fixture.smart.undoDenial()
        await select("Getting Started")
        #expect(chip.current?.content.kind == .translateButton)
    }

    @Test func anAppWithNoBundleIDCannotBeHiddenFromTheButton() async throws {
        await fixture.start()
        fixture.accessibility.application = FocusedApplication(processID: 42, bundleID: nil)
        await select(heading)
        #expect(try #require(chip.current).content.deny == nil)
    }

    // MARK: the log

    @Test func theLogSaysWhyAndWhenOnlyInCodes() async throws {
        await fixture.start()
        await select(heading)
        #expect(Array(log.lines.suffix(3)) == ["gesture pointer=1 keys=1", "skip reason=shape-name", "button shown reason=shape-name"])
        try #require(chip.current).content.open()
        #expect(log.lines.last == "button clicked")
        #expect(!log.lines.contains("chip shown"))
    }

    @Test func noLineHoldsWhatWasSelected() async throws {
        await fixture.start()
        let secrets = ["Zebraquartz", "Marmalade", "Plumbus"]
        await select("\(secrets[0]) Insights")
        try #require(chip.current).content.open()
        await select("\(secrets[1]) Insights")
        await select("\(secrets[2]) Insights")
        #expect(log.lines(startingWith: "button shown").count == 3)
        for line in log.lines {
            for secret in secrets { #expect(!line.contains(secret), "\(line)") }
        }
    }

    @Test func theLinesAreBuiltFromCodes() {
        #expect(SelectionLogLine.buttonShown(reason: .shapeName).text == "button shown reason=shape-name")
        #expect(SelectionLogLine.buttonShown(reason: .lowConfidence).text == "button shown reason=low-confidence")
        #expect(SelectionLogLine.buttonShown(reason: .sameLanguage).text == "button shown reason=same-language")
        #expect(SelectionLogLine.buttonShown(reason: .noHint).text == "button shown reason=no-hint")
        let clicked: SelectionLogLine = "button clicked"
        #expect(clicked.text == "button clicked")
    }
}

/// Which reason ends in a button and which in nothing.
@Suite struct SelectionButtonDecisionTableTests {
    static let soft: Set<SelectionSkip> = [.shapeName, .shapeShort, .lowConfidence, .sameLanguage, .noHint]

    @Test(arguments: SelectionSkip.allCases)
    func eachReasonIsAButtonOrNothing(reason: SelectionSkip) {
        #expect(reason.offersButton == Self.soft.contains(reason), "\(reason.rawValue)")
    }

    @Test func theReasonsThatAreOnlyAGuessAreTheOnesThatGetIt() {
        #expect(SelectionSkip.allCases.filter(\.offersButton).count == 5)
        #expect(SelectionSkip.shapeShort.offersButton)
        #expect(SelectionSkip.shapeName.offersButton)
        #expect(SelectionSkip.lowConfidence.offersButton)
        #expect(SelectionSkip.sameLanguage.offersButton)
        #expect(SelectionSkip.noHint.offersButton)
    }

    @Test(arguments: [
        SelectionSkip.shapeCode, .none, .secure, .denied, .notTrusted, .ownApp, .tooLong, .blank,
        .noFrontApp, .cooldown, .unresponsive, .unchanged, .unsupportedLanguage, .noConversion, .cancelled,
    ])
    func theseNeverGetIt(reason: SelectionSkip) {
        #expect(!reason.offersButton, "\(reason.rawValue)")
    }

    @Test func theShapeCodesAreSplit() {
        #expect(SelectionSkip.shapeName.rawValue == "shape-name")
        #expect(SelectionSkip.shapeCode.rawValue == "shape-code")
        #expect(SelectionSkip.shapeShort.rawValue == "shape-short")
    }
}
