import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// "Bôi đen là hiểu" from the first mouse-up to the chip on screen, with fake input, fake Accessibility and a fake window:
/// nothing here observes, reads or posts anything real.
@Suite struct SmartSelectionTests {
    let fixture = ModuleFixture()
    let english = "The quick brown fox jumps over the lazy dog"
    let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")

    func start() async {
        await fixture.start()
    }

    var chip: FakeChipWindow { fixture.chipWindow }

    // MARK: when it watches

    @Test func watchesOnceStartedWithTheSettingOn() async {
        await start()
        #expect(fixture.input.isRunning)
        #expect(fixture.input.starts == 1)
    }

    @Test func doesNotWatchWithTheSettingOff() async {
        fixture.set(false, for: \.smartSelection)
        await start()
        #expect(!fixture.input.isRunning)
        #expect(fixture.input.starts == 0)
    }

    @Test func turningTheSettingOffStopsWatchingAndTakesTheChipAway() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.isVisible)
        fixture.set(false, for: \.smartSelection)
        await eventually { !fixture.input.isRunning }
        #expect(!fixture.input.isRunning)
        #expect(!chip.isVisible)
    }

    @Test func turningItBackOnWatchesAgain() async {
        await start()
        fixture.set(false, for: \.smartSelection)
        await eventually { !fixture.input.isRunning }
        fixture.set(true, for: \.smartSelection)
        await eventually { fixture.input.isRunning }
        #expect(fixture.input.isRunning)
        #expect(fixture.input.starts == 2)
    }

    @Test func watchesOnlyWhileSomethingWouldBeShown() async {
        fixture.set(false, for: \.selectionChip)
        await start()
        #expect(!fixture.input.isRunning)
        fixture.set(true, for: \.selectionActivity)
        await eventually { fixture.input.isRunning }
        #expect(fixture.input.isRunning)
        fixture.set(false, for: \.selectionActivity)
        await eventually { !fixture.input.isRunning }
        #expect(!fixture.input.isRunning)
    }

    // MARK: key-ups need Accessibility, the mouse does not

    @Test func keysAreWatchedFromTheStartWhenAccessibilityIsGranted() async {
        await start()
        #expect(fixture.input.watchesKeys)
    }

    @Test func withoutAccessibilityOnlyTheMouseIsWatchedUntilItIsGranted() async {
        fixture.accessibility.isTrusted = false
        await start()
        #expect(fixture.input.isRunning)
        #expect(!fixture.input.watchesKeys)
        #expect(fixture.input.starts == 1)
        // Granted while running: the next mouse gesture starts listening to keys as well, without another drag being lost.
        fixture.accessibility.isTrusted = true
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.input.watchesKeys)
        #expect(fixture.input.starts == 2)
        #expect(chip.isVisible)
        await fixture.dragSelecting("10 kg")
        #expect(fixture.input.starts == 2)
    }

    @Test func stoppingTheModuleStopsWatchingAndHidesTheChip() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.isVisible)
        await fixture.module.stop()
        #expect(!fixture.input.isRunning)
        #expect(!chip.isVisible)
        #expect(fixture.previewEngine.invalidations == 1)
    }

    @Test func aDragAfterTheModuleStoppedDoesNothing() async {
        await start()
        await fixture.module.stop()
        fixture.input.drag(from: .zero, to: CGPoint(x: 100, y: 0))
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.accessibility.reads == 0)
    }

    // MARK: what it shows

    @Test func aDragOverAQuantityShowsItsConversionBesideTheSelection() async throws {
        await start()
        fixture.accessibility.bounds = CGRect(x: 100, y: 100, width: 200, height: 20)
        await fixture.dragSelecting("5 ft 11 in")
        let shown = try #require(chip.current)
        #expect(shown.content.text == "5 ft 11 in → 180 cm")
        #expect(shown.content.kind == .conversion)
        // 900 pt tall display: 20 pt down from the top for Accessibility is 780 from the bottom for AppKit.
        #expect(shown.anchor == CGRect(x: 100, y: 780, width: 200, height: 20))
        #expect(fixture.accessibility.reads == 1)
    }

    @Test func withoutBoundsTheChipGoesByThePointer() async throws {
        await start()
        await fixture.dragSelecting("5 ft 11 in", from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 450))
        #expect(try #require(chip.current).anchor == CGRect(x: 300, y: 450, width: 0, height: 0))
    }

    @Test func foreignTextShowsAPreviewTranslation() async throws {
        await start()
        await fixture.dragSelecting(english)
        let shown = try #require(chip.current)
        #expect(shown.content.text == "\(english) [en→vi]")
        #expect(shown.content.kind == .translation)
    }

    @Test func textAlreadyInTheTargetLanguageShowsNothing() async {
        await start()
        await fixture.dragSelecting("Hôm nay trời đẹp quá, chúng ta đi dạo nhé")
        #expect(chip.shown.isEmpty)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aKeyboardSelectionIsReadToo() async throws {
        await start()
        fixture.accessibility.standing = "5 ft 11 in"
        fixture.input.press(124, shift: true, pointer: CGPoint(x: 220, y: 330))
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(try #require(chip.current).anchor == CGRect(x: 220, y: 330, width: 0, height: 0))
    }

    @Test func nothingIsReadBeforeTheDebounceHasPassed() async {
        await start()
        fixture.accessibility.standing = "5 ft 11 in"
        fixture.input.drag(from: .zero, to: CGPoint(x: 100, y: 0))
        fixture.harness.scheduler.advance(by: .milliseconds(249))
        #expect(fixture.accessibility.reads == 0)
        #expect(fixture.accessibility.lengthReads == 0)
    }

    @Test func aPlainClickReadsNothing() async {
        await start()
        fixture.accessibility.standing = "5 ft 11 in"
        fixture.input.click(at: CGPoint(x: 100, y: 100))
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.accessibility.reads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func theChromiumSettingDecidesWhetherAChromeSelectionTurnsItsAccessibilityOn() async {
        await start()
        fixture.set(false, for: \.useChromiumAccessibility)
        fixture.focus("com.google.Chrome")
        await fixture.dragSelecting(nil)
        #expect(fixture.accessibility.enabled.isEmpty)
        fixture.set(true, for: \.useChromiumAccessibility)
        await fixture.dragSelecting(nil)
        #expect(fixture.accessibility.enabled == ["AXEnhancedUserInterface"])
    }

    // MARK: what it ignores

    @Test func withoutAccessibilityNothingIsRead() async {
        await start()
        fixture.accessibility.isTrusted = false
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(fixture.accessibility.lengthReads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func aPasswordFieldIsNeverReadAndShowsNothing() async {
        await start()
        fixture.accessibility.isSecureField = true
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(fixture.accessibility.boundsReads == 0)
        #expect(chip.shown.isEmpty)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func myNotchsOwnWindowsAreNeverRead() async {
        await start()
        fixture.accessibility.application = FocusedApplication(processID: getpid(), bundleID: "io.lucasvu.mynotch")
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(fixture.accessibility.lengthReads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func anAppOnTheDenyListIsNeverRead() async {
        fixture.set(["com.apple.Notes", "com.apple.Safari"], for: \.selectionDenyList)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(fixture.accessibility.lengthReads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func aDenyListChangedWhileRunningApplies() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.isVisible)
        let count = chip.shown.count
        fixture.set(["com.apple.Safari"], for: \.selectionDenyList)
        await fixture.dragSelecting("10 kg")
        #expect(chip.shown.count == count)
        #expect(!chip.isVisible)
    }

    @Test func moreThanTwoThousandCharactersAreIgnored() async {
        await start()
        await fixture.dragSelecting(String(repeating: "a", count: 2_001))
        #expect(chip.shown.isEmpty)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aRangeKnownToBeTooLongIsNotFetchedAtAll() async {
        await start()
        fixture.accessibility.length = 2_001
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func aRangeKnownToBeEmptyIsNotFetchedEither() async {
        await start()
        fixture.accessibility.length = 0
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.accessibility.reads == 0)
        #expect(chip.shown.isEmpty)
    }

    @Test func blankOrMissingSelectionsShowNothing() async {
        await start()
        await fixture.dragSelecting("   \n ")
        await fixture.dragSelecting(nil)
        #expect(chip.shown.isEmpty)
    }

    // MARK: one chip at a time

    @Test func theSameSelectionIsNotShownAgainWhileItsChipIsUp() async {
        await start()
        await fixture.dragSelecting(english)
        let count = chip.shown.count
        #expect(chip.isVisible)
        // Select all, with the same text still selected: no new decision and no new chip.
        fixture.input.press(0, command: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(chip.shown.count == count)
        #expect(chip.isVisible)
        #expect(fixture.previewEngine.requests.count == 1)
    }

    @Test func theSameSelectionShowsAgainOnceItsChipHasGone() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(!chip.isVisible)
        let count = chip.shown.count
        fixture.input.press(0, command: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(chip.shown.count == count + 1)
        #expect(chip.isVisible)
    }

    @Test func aNewSelectionReplacesTheChip() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.accessibility.standing = "10 kg"
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(chip.current?.content.text.hasPrefix("10 kg") == true)
    }

    @Test func aSelectionWithNothingToShowTakesTheChipAway() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.isVisible)
        fixture.accessibility.standing = "Hôm nay trời đẹp quá, chúng ta đi dạo nhé"
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(!chip.isVisible)
    }

    @Test func aSelectionThatCannotBeReadAnyMoreTakesTheChipAway() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.accessibility.standing = nil
        fixture.input.press(124, shift: true)
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await fixture.smart.reading?.value
        #expect(!chip.isVisible)
    }

    // MARK: when the chip goes

    @Test func aClickElsewhereDismissesIt() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.input.click(at: CGPoint(x: 900, y: 100))
        #expect(!chip.isVisible)
    }

    @Test func anyKeyThatIsNotASelectionDismissesIt() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.input.press(53)
        #expect(!chip.isVisible)
    }

    @Test func aSelectionKeyDoesNotDismissItBeforeTheNewReading() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.input.press(124, shift: true)
        #expect(chip.isVisible)
    }

    @Test func theSourceAppLeavingTheFrontDismissesIt() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.input.send(.applicationActivated(42))
        #expect(chip.isVisible)
        fixture.input.send(.applicationActivated(777))
        #expect(!chip.isVisible)
    }

    @Test func itGoesAfterFiveSeconds() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        fixture.harness.scheduler.advance(by: .milliseconds(4_999))
        #expect(chip.isVisible)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(!chip.isVisible)
    }

    @Test func hoveringKeepsItAndLeavingLetsItGo() async throws {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        let content = try #require(chip.current?.content)
        content.hover(true)
        fixture.harness.scheduler.advance(by: .seconds(60))
        #expect(chip.isVisible)
        content.hover(false)
        fixture.harness.scheduler.advance(by: .seconds(2))
        #expect(!chip.isVisible)
    }

    // MARK: work that a newer gesture or a click makes stale

    @Test func aPreviewStillBeingMadeIsDroppedWhenTheUserClicksElsewhere() async {
        await start()
        fixture.previewEngine.holds = true
        fixture.accessibility.standing = english
        fixture.input.drag(from: .zero, to: CGPoint(x: 100, y: 0))
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await eventually { fixture.previewEngine.waiting }
        let reading = fixture.smart.reading
        fixture.input.click(at: CGPoint(x: 900, y: 100))
        fixture.previewEngine.release()
        await reading?.value
        #expect(chip.shown.isEmpty)
    }

    @Test func aPreviewStillBeingMadeIsDroppedWhenAnotherAppComesToTheFront() async {
        await start()
        fixture.previewEngine.holds = true
        fixture.accessibility.standing = english
        fixture.input.drag(from: .zero, to: CGPoint(x: 100, y: 0))
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await eventually { fixture.previewEngine.waiting }
        let reading = fixture.smart.reading
        fixture.input.send(.applicationActivated(777))
        fixture.previewEngine.release()
        await reading?.value
        #expect(chip.shown.isEmpty)
    }

    @Test func aNewerSelectionWinsOverAPreviewStillBeingMade() async {
        await start()
        fixture.previewEngine.holds = true
        fixture.accessibility.standing = english
        fixture.input.drag(from: .zero, to: CGPoint(x: 100, y: 0))
        fixture.harness.scheduler.advance(by: .milliseconds(250))
        await eventually { fixture.previewEngine.waiting }
        let first = fixture.smart.reading
        fixture.previewEngine.holds = false
        await fixture.dragSelecting("5 ft 11 in")
        fixture.previewEngine.release()
        await first?.value
        #expect(chip.shown.map(\.content.text) == ["5 ft 11 in → 180 cm"])
        // The old reading ending late must not take the newer chip away either.
        #expect(chip.current?.content.text == "5 ft 11 in → 180 cm")
    }

    // MARK: "Mở"

    @Test func openingShowsTheFullResultInTheTranslationTabWithItsSourceForReplacing() async throws {
        await start()
        await fixture.dragSelecting(english)
        let content = try #require(chip.current?.content)
        content.open()
        await fixture.translated()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == english)
        #expect(fixture.state.output == "\(english) [en→vi]")
        #expect(fixture.state.selectionSource == SelectionSource(text: english, application: safari))
        #expect(fixture.state.showsReplace)
        #expect(!chip.isVisible)
    }

    @Test func openingTranslatesEvenWhenAutoTranslateIsOff() async throws {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await start()
        await fixture.dragSelecting(english)
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.state.output == "\(english) [en→vi]")
    }

    @Test func openingAConversionShowsItInTheTab() async throws {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        try #require(chip.current).content.open()
        await fixture.translated()
        #expect(fixture.state.conversions.map(\.source) == ["5 ft 11 in"])
        #expect(fixture.state.selectionSource?.text == "5 ft 11 in")
    }

    @Test func aRemoteEngineIsAskedOnlyWhenTheUserOpensTheResult() async throws {
        _ = fixture.keyStore.save("fake-key", for: .googleKey)
        fixture.set("google", for: \.engine)
        await start()
        await fixture.dragSelecting(english)
        await fixture.dragSelecting("5 ft 11 in")
        await fixture.dragSelecting(english)
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.keyStore.loadCount == 0)
        #expect(fixture.engine.requests.isEmpty)
        try #require(chip.current).content.open()
        await fixture.translated()
        await eventually { !fixture.transport.requests.isEmpty }
        #expect(fixture.transport.requests.count == 1)
    }

    // MARK: "Không hiện trong app này"

    @Test func denyingTheAppFromTheChipRemembersItAndHidesTheChip() async throws {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        let deny = try #require(chip.current?.content.deny)
        deny()
        #expect(fixture.harness.settingsEnvironment(for: "translation")!.settings.value(fixture.keys.selectionDenyList) == ["com.apple.Safari"])
        #expect(!chip.isVisible)
        let reads = fixture.accessibility.reads
        await fixture.dragSelecting("10 kg")
        #expect(fixture.accessibility.reads == reads)
        #expect(!chip.isVisible)
    }

    @Test func denyingTwiceKeepsOneEntry() async throws {
        fixture.set(["com.apple.Notes"], for: \.selectionDenyList)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        let deny = try #require(chip.current?.content.deny)
        deny()
        deny()
        #expect(fixture.harness.settingsEnvironment(for: "translation")!.settings.value(fixture.keys.selectionDenyList) == ["com.apple.Notes", "com.apple.Safari"])
    }

    @Test func anAppWithoutABundleIDCannotBeDenied() async throws {
        await start()
        fixture.accessibility.application = FocusedApplication(processID: 42, bundleID: nil)
        await fixture.dragSelecting("5 ft 11 in")
        #expect(try #require(chip.current).content.deny == nil)
    }

    // MARK: the chip setting and the notch activity

    @Test func withTheChipOffNothingIsShownBesideTheSelection() async {
        fixture.set(true, for: \.selectionActivity)
        fixture.set(false, for: \.selectionChip)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.shown.isEmpty)
        #expect(fixture.harness.activities.current != nil)
    }

    @Test func theNotchActivityIsOffByDefault() async {
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.activities.entries.isEmpty)
    }

    @Test func theNotchActivityCarriesTheResultAndGoesWithTheChip() async {
        fixture.set(true, for: \.selectionActivity)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        let entry = fixture.harness.activities.current
        #expect(entry?.module == "translation")
        #expect(entry?.activity.summary == "5 ft 11 in → 180 cm")
        fixture.input.click(at: CGPoint(x: 900, y: 100))
        #expect(fixture.harness.activities.entries.isEmpty)
    }

    @Test func theNotchActivityEndsOnItsOwnEvenWhileThePointerHoldsTheChip() async throws {
        fixture.set(true, for: \.selectionActivity)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        try #require(chip.current).content.hover(true)
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(chip.isVisible)
        #expect(fixture.harness.activities.entries.isEmpty)
    }

    @Test func theNotchActivityEndsAfterFiveSeconds() async {
        fixture.set(true, for: \.selectionActivity)
        await start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.harness.activities.entries.count == 1)
        fixture.harness.scheduler.advance(by: .seconds(5))
        #expect(fixture.harness.activities.entries.isEmpty)
    }

    @Test func settingsHaveTheDefaultsTheBriefAsks() async {
        await start()
        #expect(fixture.keys.smartSelection.defaultValue == true)
        #expect(fixture.keys.selectionChip.defaultValue == true)
        #expect(fixture.keys.selectionActivity.defaultValue == false)
        #expect(fixture.keys.selectionDenyList.defaultValue.isEmpty)
    }
}
