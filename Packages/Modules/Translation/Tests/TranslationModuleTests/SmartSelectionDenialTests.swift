import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// Hiding the chip for an app is easy to do by accident and was too final: it asks from a "⋯" menu, says what it did in the
/// notch, and can be undone for a few seconds. And a translation reaches the chip whole, with the first line of the original.
@Suite struct SmartSelectionDenialTests {
    let fixture = ModuleFixture()
    let english = "The quick brown fox jumps over the lazy dog"
    let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")

    var chip: FakeChipWindow { fixture.chipWindow }
    var denyList: [String] { fixture.harness.settingsEnvironment(for: "translation")!.settings.value(fixture.keys.selectionDenyList) }

    func deny() async throws {
        await fixture.dragSelecting("5 ft 11 in")
        let deny = try #require(chip.current?.content.deny)
        deny()
    }

    // MARK: hiding an app

    @Test func hidingAnAppShowsANoticeNamingItWithAnUndo() async throws {
        await fixture.start()
        try await deny()
        #expect(denyList == ["com.apple.Safari"])
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(fixture.smart.pendingUndo?.appName == "Safari")
        #expect(SelectionDenialNotice.title(appName: "Chrome") == "Đã ẩn trong Chrome")
        #expect(fixture.selectionLog.contains("deny added=1"))
    }

    @Test func undoPutsTheListBackAndTheAppIsReadAgain() async throws {
        fixture.set(["com.apple.Notes"], for: \.selectionDenyList)
        await fixture.start()
        try await deny()
        #expect(denyList == ["com.apple.Notes", "com.apple.Safari"])
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Notes"])
        #expect(fixture.selectionLog.contains("deny undone=1"))
        await fixture.dragSelecting("10 kg")
        #expect(chip.current?.content.text.hasPrefix("10 kg") == true)
    }

    @Test func undoClosesTheNotice() async throws {
        await fixture.start()
        try await deny()
        let closes = fixture.harness.presenter.closeCount
        fixture.smart.undoDenial()
        #expect(fixture.harness.presenter.closeCount == closes + 1)
    }

    @Test func undoIsOnlyThereForFiveSeconds() async throws {
        await fixture.start()
        try await deny()
        fixture.harness.scheduler.advance(by: .milliseconds(4_999))
        #expect(fixture.smart.pendingUndo != nil)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        #expect(fixture.smart.pendingUndo == nil)
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Safari"])
    }

    @Test func undoDoesNothingTwice() async throws {
        fixture.set(["com.apple.Notes"], for: \.selectionDenyList)
        await fixture.start()
        try await deny()
        fixture.smart.undoDenial()
        // The user adds it again by hand in Settings; a second undo must not take it out.
        fixture.set(["com.apple.Notes", "com.apple.Safari"], for: \.selectionDenyList)
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Notes", "com.apple.Safari"])
    }

    @Test func undoNeverTakesOutAnAppThatWasAlreadyOnTheList() async {
        fixture.set(["com.apple.Safari"], for: \.selectionDenyList)
        await fixture.start()
        fixture.smart.deny(safari)
        #expect(fixture.selectionLog.contains("deny added=0"))
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Safari"])
    }

    @Test func aSecondDenialReplacesTheUndo() async {
        await fixture.start()
        let notes = FocusedApplication(processID: 43, bundleID: "com.apple.Notes")
        fixture.smart.deny(safari)
        fixture.smart.deny(notes)
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Safari"])
    }

    @Test func anAppWithoutABundleIDCannotBeHiddenAndShowsNoNotice() async {
        await fixture.start()
        fixture.smart.deny(FocusedApplication(processID: 44, bundleID: nil))
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(fixture.smart.pendingUndo == nil)
    }

    @Test func theChipStillOffersHidingTheApp() async throws {
        await fixture.start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(try #require(chip.current).content.deny != nil)
        // Offering it does not do it: nothing is hidden until it is chosen.
        #expect(denyList.isEmpty)
        #expect(fixture.harness.presenter.toastCount == 0)
    }

    // MARK: the whole translation

    @Test func aTranslationChipCarriesTheWholeTranslationAndTheFirstLineOfTheOriginal() async throws {
        await fixture.start()
        let original = "\(english)\nand then the dog sleeps all day long"
        await fixture.dragSelecting(original)
        let content = try #require(chip.current).content
        #expect(content.kind == .translation)
        #expect(content.text == "\(original) [en→vi]")
        #expect(content.caption == english)
    }

    @Test func aLongOriginalsCaptionIsCut() async throws {
        await fixture.start()
        let first = String(repeating: english + ", ", count: 6)
        await fixture.dragSelecting(first + "\nand more words after it all")
        let caption = try #require(chip.current?.content.caption)
        #expect(caption.count == SelectionHint.captionLength)
        #expect(caption.hasSuffix("…"))
    }

    @Test func aConversionAndAButtonHaveNoCaption() async throws {
        await fixture.start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(try #require(chip.current?.content).caption == nil)
        fixture.previewEngine.failure = .notInstalled
        await fixture.dragSelecting("The lazy dog jumps over the quick brown fox again today")
        #expect(try #require(chip.current?.content).caption == nil)
    }

    @Test func aTranslationIsNeverCutOnItsWayToTheChip() async throws {
        await fixture.start()
        let long = (1...30).map { "\(english) number \($0)." }.joined(separator: "\n")
        await fixture.dragSelecting(long)
        let content = try #require(chip.current?.content)
        #expect(content.text == "\(long) [en→vi]")
        #expect(content.text.split(separator: "\n").count == 30)
    }

    @Test func theNotchActivityKeepsToTheFirstLineOfATranslation() async {
        fixture.set(true, for: \.selectionActivity)
        await fixture.start()
        await fixture.dragSelecting("\(english)\nand then the dog sleeps all day long")
        #expect(fixture.harness.activities.current?.activity.summary == "\(english)")
    }

    @Test func theCaptionIsTheFirstNonBlankLineTrimmed() {
        #expect(SelectionHint.caption(of: "\n  Hello there  \nsecond") == "Hello there")
        #expect(SelectionHint.caption(of: "   \n  ") == nil)
        #expect(SelectionHint.caption(of: "") == nil)
    }
}
