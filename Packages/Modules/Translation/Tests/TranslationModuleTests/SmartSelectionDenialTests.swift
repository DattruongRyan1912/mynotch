import CoreGraphics
import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
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

    // MARK: how long the undo lasts

    @Test func theNoticesAskToStayForTheirTime() async throws {
        fixture.accessibility.isTrusted = false
        await fixture.start()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(fixture.toasts.durations == [.seconds(10)])
        // Hiding an app needs the permission and a chip, so it is made in a second run.
        let second = ModuleFixture()
        await second.start()
        await second.dragSelecting("5 ft 11 in")
        let deny = try #require(second.chipWindow.current?.content.deny)
        deny()
        #expect(second.toasts.durations == [.seconds(5)])
    }

    @Test func undoWorksForAsLongAsTheNoticeIsOnScreen() async throws {
        await fixture.start()
        try await deny()
        // The notch keeps a notice up while the pointer is in it, which can be much longer than it asked for.
        fixture.harness.scheduler.advance(by: .seconds(600))
        #expect(fixture.smart.pendingUndo != nil)
        fixture.smart.undoDenial()
        #expect(denyList.isEmpty)
    }

    @Test func undoEndsWhenTheNoticeIsGone() async throws {
        await fixture.start()
        try await deny()
        let id = try #require(fixture.smart.pendingUndo?.id)
        fixture.smart.denialNoticeGone(id)
        #expect(fixture.smart.pendingUndo == nil)
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Safari"])
    }

    @Test func aNoticeThatWasReplacedGoingDoesNotEndTheNewerUndo() async {
        await fixture.start()
        let notes = FocusedApplication(processID: 43, bundleID: "com.apple.Notes")
        fixture.smart.deny(safari)
        let first = fixture.smart.pendingUndo?.id
        fixture.smart.deny(notes)
        fixture.smart.denialNoticeGone(first ?? -1)
        #expect(fixture.smart.pendingUndo?.bundleID == "com.apple.Notes")
        fixture.smart.undoDenial()
        #expect(denyList == ["com.apple.Safari"])
    }

    @Test func theNoticeTellsWhenItLeavesTheScreen() async throws {
        let log = HoverLog()
        let notice = SelectionDenialNotice(appName: "Chrome", undo: {}, gone: { log.record(false) })
        let hosting = NSHostingView(rootView: AnyView(notice.frame(width: 300, height: 40)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(log.values.isEmpty)
        hosting.rootView = AnyView(EmptyView())
        for _ in 0..<200 where log.values.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(log.values == [false])
        window.contentView = nil
    }

    @Test func bothNoticesCanBeDrawn() {
        let grant = NSHostingView(rootView: SelectionAccessibilityNotice(grant: {}))
        #expect(grant.fittingSize.width > 150)
        let denial = NSHostingView(rootView: SelectionDenialNotice(appName: "Chrome", undo: {}, gone: {}))
        #expect(denial.fittingSize.width > 150)
    }

    @Test func theSameTextSelectedAgainAfterAnUndoShowsAgain() async throws {
        await fixture.start()
        try await deny()
        fixture.smart.undoDenial()
        await fixture.dragSelecting("5 ft 11 in")
        #expect(chip.isVisible)
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

    @Test func aCutPreviewsChipSaysSoAndAWholeOnesDoesNot() async throws {
        await fixture.start()
        await fixture.dragSelecting(String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 30))
        let cut = try #require(chip.current?.content)
        #expect(cut.note == "Mở để dịch đủ")
        #expect(cut.text.hasSuffix("…"))
        await fixture.dragSelecting(english)
        let whole = try #require(chip.current?.content)
        #expect(whole.note == nil)
        #expect(!whole.text.hasSuffix("…"))
    }

    @Test func aTranslationThatFitsThePreviewIsNeverCutOnItsWayToTheChip() async throws {
        await fixture.start()
        // Twelve lines, about 575 characters: under what a preview translates, so all of it is.
        let long = (1...12).map { "\(english) \($0)." }.joined(separator: "\n")
        #expect(long.count < SelectionDecider.previewLimit)
        await fixture.dragSelecting(long)
        let content = try #require(chip.current?.content)
        #expect(content.text == "\(long) [en→vi]")
        #expect(content.text.split(separator: "\n").count == 12)
        #expect(content.note == nil)
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
