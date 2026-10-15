import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// What "Bôi đen là hiểu" tells the log, so that a selection that shows nothing can be explained from the unified log alone,
/// and the chip and the notice for the cases that used to show nothing at all. Every message is a code, never any text.
@Suite struct SmartSelectionDiagnosticsTests {
    let fixture = ModuleFixture()
    let english = "The quick brown fox jumps over the lazy dog"

    var log: FakeSelectionLog { fixture.selectionLog }
    var chip: FakeChipWindow { fixture.chipWindow }

    func start() async {
        await fixture.start()
    }

    /// The lines one gesture wrote, after the ones from starting.
    func lines(of gesture: () async -> Void) async -> [String] {
        let before = log.lines.count
        await gesture()
        return Array(log.lines.dropFirst(before))
    }

    // MARK: starting

    @Test func startingSaysWhetherItIsWatchingTrustedAndListeningToKeys() async {
        await start()
        #expect(log.lines.first == "start watcher=1 trusted=1 keys=1")
    }

    @Test func startingWithoutAccessibilitySaysSo() async {
        fixture.accessibility.isTrusted = false
        await start()
        #expect(log.lines.first == "start watcher=1 trusted=0 keys=0")
    }

    @Test func startingWithTheFeatureOffSaysItIsNotWatching() async {
        fixture.set(false, for: \.smartSelection)
        await start()
        #expect(log.lines.first == "start watcher=0 trusted=1 keys=0")
    }

    @Test func startingWithNothingToShowItWithSaysItIsNotWatching() async {
        fixture.set(false, for: \.selectionChip)
        await start()
        #expect(log.lines.first == "start watcher=0 trusted=1 keys=0")
    }

    @Test func gainingAccessibilityWhileRunningIsLogged() async {
        fixture.accessibility.isTrusted = false
        await start()
        fixture.accessibility.isTrusted = true
        _ = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(log.contains("keys on trusted=1"))
    }

    // MARK: every gesture

    @Test func aMouseGestureIsLoggedWithItsSource() async {
        await start()
        let written = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(written.first == "gesture pointer=1 keys=1")
    }

    @Test func aKeyboardGestureIsLogged() async {
        await start()
        fixture.accessibility.standing = "5 ft 11 in"
        let written = await lines {
            fixture.input.press(124, shift: true)
            fixture.harness.scheduler.advance(by: .milliseconds(250))
            await fixture.smart.reading?.value
        }
        #expect(written.first == "gesture pointer=0 keys=1")
    }

    @Test func aGestureWithoutAccessibilityIsLoggedWithKeysOff() async {
        fixture.accessibility.isTrusted = false
        await start()
        let written = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(written.first == "gesture pointer=1 keys=0")
    }

    @Test func aPlainClickIsNotAGesture() async {
        await start()
        let written = await lines {
            fixture.input.click(at: CGPoint(x: 5, y: 5))
            fixture.harness.scheduler.advance(by: .seconds(1))
        }
        #expect(written.isEmpty)
    }

    // MARK: why nothing shows

    /// The reason the gesture ended with, after the gesture line.
    func skipLine(_ text: String?, prepare: () -> Void = {}) async -> [String] {
        await start()
        prepare()
        return await lines { await fixture.dragSelecting(text) }
    }

    @Test func notTrusted() async {
        fixture.accessibility.isTrusted = false
        let written = await skipLine("5 ft 11 in")
        // The first one of the run also says why nothing shows, in the notch.
        #expect(written == ["gesture pointer=1 keys=0", "skip reason=not-trusted", "notice accessibility"])
        let again = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(again == ["gesture pointer=1 keys=0", "skip reason=not-trusted"])
    }

    @Test func noFrontApp() async {
        let written = await skipLine("5 ft 11 in") { fixture.accessibility.application = nil }
        #expect(written == ["gesture pointer=1 keys=1", "skip reason=no-front-app"])
    }

    @Test func myNotchItself() async {
        let written = await skipLine("5 ft 11 in") {
            fixture.accessibility.application = FocusedApplication(processID: getpid(), bundleID: "io.lucasvu.mynotch")
        }
        #expect(written.last == "skip reason=own-app")
    }

    @Test func anAppOnTheDenyList() async {
        fixture.set(["com.apple.Safari"], for: \.selectionDenyList)
        let written = await skipLine("5 ft 11 in")
        #expect(written == ["gesture pointer=1 keys=1", "skip reason=denied"])
    }

    @Test func aPasswordManager() async {
        let written = await skipLine("5 ft 11 in") {
            fixture.accessibility.application = FocusedApplication(processID: 42, bundleID: "com.1password.1password")
        }
        #expect(written.last == "skip reason=denied")
    }

    @Test func anAppThatDidNotAnswerAndThenTheCoolDown() async {
        let first = await skipLine("5 ft 11 in") { fixture.accessibility.hangs = true }
        #expect(first.last == "skip reason=unresponsive")
        let second = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(second.last == "skip reason=cooldown")
    }

    @Test func secureInput() async {
        let written = await skipLine("5 ft 11 in") { fixture.accessibility.secureInputHolders = [42] }
        #expect(written.last == "skip reason=secure")
    }

    @Test func nothingSelected() async {
        let written = await skipLine(nil)
        #expect(written.last == "skip reason=none")
    }

    @Test func aPasswordFieldReadsAsNothing() async {
        let written = await skipLine("hunter2") { fixture.accessibility.isSecureField = true }
        #expect(written.last == "skip reason=none")
    }

    @Test func tooMuchSelected() async {
        let byLength = await skipLine("5 ft 11 in") { fixture.accessibility.length = 2_001 }
        #expect(byLength.last == "skip reason=too-long")
        let byText = await lines {
            fixture.accessibility.length = nil
            await fixture.dragSelecting(String(repeating: "a", count: 2_001))
        }
        #expect(byText.last == "skip reason=too-long")
    }

    @Test func onlyBlankText() async {
        let written = await skipLine("   \n ")
        #expect(written.last == "skip reason=blank")
    }

    @Test func theSameSelectionAgain() async {
        let first = await skipLine("5 ft 11 in")
        #expect(first.contains("hint kind=conversion"))
        let second = await lines { await fixture.dragSelecting("5 ft 11 in") }
        #expect(second.last == "skip reason=unchanged")
    }

    @Test func aTextThatIsNotProse() async {
        let url = await skipLine("https://example.com/blog/2026/10/why-we-moved") 
        #expect(url.last == "skip reason=shape")
        let code = await lines { await fixture.dragSelecting("let value = compute(input)") }
        #expect(code.last == "skip reason=shape")
        let oneWord = await lines { await fixture.dragSelecting("Hello") }
        #expect(oneWord.last == "skip reason=shape")
    }

    @Test func aTextInTheTargetLanguage() async {
        let written = await skipLine("Hôm nay trời đẹp quá, chúng ta đi dạo nhé")
        #expect(written.last == "skip reason=same-language")
    }

    @Test func aGuessThatIsNotSureEnough() async {
        // The recognizer gives this about a third of a chance of being English.
        let written = await skipLine("Hello world")
        #expect(written.last == "skip reason=low-confidence")
    }

    @Test func aLanguageThatCannotBeTranslated() async {
        let written = await skipLine("안녕하세요 여러분 만나서 반갑습니다")
        #expect(written.last == "skip reason=unsupported-language")
    }

    @Test func aPriceThatCouldNotBeConverted() async {
        let written = await skipLine("$12") { fixture.set(true, for: \.convertCurrency) }
        #expect(written.last == "skip reason=no-conversion")
    }

    // MARK: what was shown

    @Test func aConversionIsLoggedWithItsChip() async {
        let written = await skipLine("5 ft 11 in")
        #expect(written == ["gesture pointer=1 keys=1", "hint kind=conversion", "chip shown"])
    }

    @Test func aPreviewIsLoggedWithItsChip() async {
        let written = await skipLine(english)
        #expect(written == ["gesture pointer=1 keys=1", "hint kind=preview", "chip shown"])
    }

    @Test(arguments: [
        (TranslationFailure.notInstalled, "not-installed"), (.unsupported, "unsupported"), (.failed("boom"), "error"),
    ])
    func aPreviewThatCouldNotBeMadeIsLoggedWithWhyAndGetsTheButton(failure: TranslationFailure, code: String) async {
        let written = await skipLine(english) { fixture.previewEngine.failure = failure }
        #expect(written == ["gesture pointer=1 keys=1", "preview failed reason=\(code)", "hint kind=button", "chip shown"])
    }

    @Test func aSupersededPreviewIsNotAFailure() async {
        let written = await skipLine(english) { fixture.previewEngine.failure = .cancelled }
        #expect(written == ["gesture pointer=1 keys=1", "skip reason=cancelled"])
    }

    @Test func theActivityIsLoggedWhenTheChipIsOff() async {
        fixture.set(false, for: \.selectionChip)
        fixture.set(true, for: \.selectionActivity)
        let written = await skipLine("5 ft 11 in")
        #expect(written == ["gesture pointer=1 keys=1", "hint kind=conversion", "activity shown"])
    }

    // MARK: only codes

    @Test func noLineEverHoldsWhatTheUserSelected() async {
        await start()
        let secrets = ["zebraquartz", "hunter2secret", "marmalade-token", "plumbus"]
        await fixture.dragSelecting("\(secrets[0]) 5 ft 11 in")
        await fixture.dragSelecting("The \(secrets[1]) jumps over the lazy dog and the quick brown fox")
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting("The \(secrets[2]) sleeps beside the quick brown fox and lazy dog")
        fixture.accessibility.isSecureField = true
        await fixture.dragSelecting(secrets[3])
        fixture.accessibility.isSecureField = false
        await fixture.dragSelecting("let \(secrets[0]) = compute(\(secrets[1]))")
        #expect(!log.lines.isEmpty)
        for line in log.lines {
            for secret in secrets { #expect(!line.contains(secret), "\(line)") }
        }
    }

    @Test func everyLineIsOneOfTheKnownShapes() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        await fixture.dragSelecting(english)
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting("The lazy dog jumps over the quick brown fox again today")
        await fixture.dragSelecting(nil)
        fixture.accessibility.isTrusted = false
        await fixture.dragSelecting("5 ft 11 in")
        let known = [
            "start watcher=", "gesture pointer=", "skip reason=", "hint kind=", "preview failed reason=", "chip shown", "activity shown",
            "keys on trusted=", "watcher ", "accessibility enabled ", "accessibility refused ", "notice ", "deny ",
        ]
        for line in log.lines {
            #expect(known.contains { line.hasPrefix($0) }, "\(line)")
            #expect(line.count < 60, "\(line)")
        }
    }

    // MARK: lines are built, not typed

    @Test func everyLineIsBuiltFromFixedWordsAndNumbers() {
        #expect(SelectionLogLine.start(watcher: true, trusted: false, keys: true).text == "start watcher=1 trusted=0 keys=1")
        #expect(SelectionLogLine.gesture(pointer: false, keys: true).text == "gesture pointer=0 keys=1")
        #expect(SelectionLogLine.skip(.sameLanguage).text == "skip reason=same-language")
        #expect(SelectionLogLine.hint(.translation).text == "hint kind=preview")
        #expect(SelectionLogLine.previewFailed(.notInstalled).text == "preview failed reason=not-installed")
        #expect(SelectionLogLine.deny(added: false).text == "deny added=0")
        #expect(SelectionLogLine.watcher(on: true, keys: false).text == "watcher on keys=0")
        #expect(SelectionLogLine.watcher(on: false, keys: false).text == "watcher off")
        let literal: SelectionLogLine = "chip shown"
        #expect(literal.text == "chip shown")
    }

    @Test func anAttributeNameThatIsNotOneOfTheTwoIsNotLogged() {
        #expect(SelectionLogLine.accessibilityEnabled("AXEnhancedUserInterface").text == "accessibility enabled attribute=AXEnhancedUserInterface")
        #expect(SelectionLogLine.accessibilityEnabled("AXManualAccessibility").text == "accessibility enabled attribute=AXManualAccessibility")
        #expect(SelectionLogLine.accessibilityEnabled("Some secret title").text == "accessibility enabled attribute=other")
        #expect(SelectionLogLine.accessibilityRefused("Some secret title").text == "accessibility refused attribute=other")
    }

    // MARK: the translate button

    @Test func theButtonChipSaysTranslateAndWhyThePreviewIsMissing() async throws {
        await start()
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting(english)
        let content = try #require(chip.current).content
        #expect(content.kind == .button)
        #expect(content.actionTitle == "Dịch")
        #expect(content.text == "Cần tải gói ngôn ngữ")
        #expect(content.deny != nil)
    }

    @Test func theButtonChipWithNoNoteHasJustTheButton() async throws {
        await start()
        fixture.previewEngine.failure = .unsupported
        await fixture.dragSelecting(english)
        let content = try #require(chip.current).content
        #expect(content.kind == .button)
        #expect(content.text.isEmpty)
        #expect(content.actionTitle == "Dịch")
    }

    @Test func otherChipsKeepTheirOpenButton() async throws {
        await start()
        await fixture.dragSelecting(english)
        #expect(try #require(chip.current).content.actionTitle == "Mở")
        await fixture.dragSelecting("5 ft 11 in")
        #expect(try #require(chip.current).content.actionTitle == "Mở")
    }

    @Test func theTranslateButtonOpensTheTabOnTheSelection() async throws {
        await start()
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting(english)
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == english)
        #expect(fixture.state.selectionSource?.text == english)
        // The tab's own engine is asked for it, which is what shows the language installer when the pack is missing.
        #expect(fixture.engine.requests.map(\.text) == [english])
        #expect(!chip.isVisible)
    }

    @Test func theTabOffersToInstallTheLanguageWhenThePackIsMissing() async throws {
        await start()
        fixture.previewEngine.failure = .notInstalled
        fixture.engine.failure = .notInstalled
        fixture.engine.statuses[LanguagePair(source: .en, target: .vi)] = .supported
        await fixture.dragSelecting(english)
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.state.banner == .notInstalled(LanguagePair(source: .en, target: .vi)))
    }

    @Test func theButtonCountsAsAnActivityToo() async {
        fixture.set(true, for: \.selectionActivity)
        await start()
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting(english)
        #expect(fixture.harness.activities.current?.activity.summary == "Cần tải gói ngôn ngữ")
        fixture.previewEngine.failure = .unsupported
        await fixture.dragSelecting("The lazy dog jumps over the quick brown fox again today")
        #expect(fixture.harness.activities.current?.activity.summary == "Dịch")
    }

    // MARK: the notice when Accessibility is missing

    @Test func theFirstGestureWithoutAccessibilityShowsOneNotice() async {
        fixture.accessibility.isTrusted = false
        await start()
        #expect(fixture.harness.presenter.toastCount == 0)
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(fixture.selectionLog.contains("notice accessibility"))
        await fixture.dragSelecting("10 kg")
        await fixture.dragSelecting(english)
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func noNoticeWhenAccessibilityIsGranted() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.presenter.toastCount == 0)
    }

    @Test func noNoticeBeforeTheUserHasSelectedAnything() async {
        fixture.accessibility.isTrusted = false
        await start()
        fixture.input.click(at: CGPoint(x: 5, y: 5))
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(fixture.harness.permissions.requested.isEmpty)
    }

    @Test func theNoticeAsksForNothingByItself() async {
        fixture.accessibility.isTrusted = false
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.permissions.requested.isEmpty)
        #expect(fixture.harness.permissions.openedSettings.isEmpty)
    }

    @Test func theNoticeIsOncePerAppRunEvenWhenTheModuleStartsAgain() async {
        fixture.accessibility.isTrusted = false
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.presenter.toastCount == 1)
        // Switched off and on in Settings: a new run of the module, but the same run of the app.
        await fixture.harness.registry.setEnabled(false, for: "translation")
        await fixture.harness.registry.setEnabled(true, for: "translation")
        #expect(fixture.input.isRunning)
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func theButtonAsksForAccessibilityAndOpensTheSystemPaneWhenItIsNotGranted() async {
        fixture.accessibility.isTrusted = false
        await start()
        fixture.harness.permissions.requestResult = .denied
        await fixture.smart.requestAccessibility().value
        #expect(fixture.harness.permissions.requested == [.accessibility])
        #expect(fixture.harness.permissions.openedSettings == [.accessibility])
    }

    @Test func theButtonOpensNothingWhenThePromptWasAnswered() async {
        fixture.accessibility.isTrusted = false
        await start()
        fixture.harness.permissions.requestResult = .granted
        await fixture.smart.requestAccessibility().value
        #expect(fixture.harness.permissions.requested == [.accessibility])
        #expect(fixture.harness.permissions.openedSettings.isEmpty)
    }

    @Test func theLedgerGivesTheNoticeOnce() {
        let notices = SelectionNotices()
        #expect(notices.claim())
        #expect(!notices.claim())
        #expect(!notices.claim())
        #expect(SelectionNotices().claim())
    }
}
