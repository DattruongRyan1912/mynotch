import CoreGraphics
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// What the chip's lifecycle did, in order.
final class ChipLog {
    private(set) var shown: [(hint: SelectionHint, anchor: CGRect)] = []
    private(set) var hides = 0
    private(set) var dismissals = 0

    func show(_ hint: SelectionHint, _ anchor: CGRect) { shown.append((hint, anchor)) }
    func hide() { hides += 1 }
    func dismissal() { dismissals += 1 }
}

/// Where the pointer is, which a test moves.
final class FakePointer {
    var location: CGPoint

    init(at location: CGPoint = CGPoint(x: 40, y: 40)) {
        self.location = location
    }
}

/// How long a chip lives and what keeps it or ends it, on a clock the test moves.
@Suite struct SelectionChipTests {
    let scheduler = ManualScheduler()
    let log = ChipLog()
    let pointer = FakePointer()
    let chip: SelectionChip
    let anchor = CGRect(x: 10, y: 20, width: 30, height: 40)

    init() {
        let (scheduler, log, pointer) = (scheduler, log, pointer)
        chip = SelectionChip(
            scheduler: scheduler, show: { log.show($0, $1) }, hide: { log.hide() }, onDismiss: { log.dismissal() },
            pointer: { pointer.location }
        )
    }

    /// The small translate button, which is for a selection that was not translated by itself.
    func button(processID: pid_t = 42) -> SelectionHint {
        SelectionHint(
            kind: .translateButton, text: "", source: SelectionSource(text: "PageSpeed Insights", application: FocusedApplication(processID: processID, bundleID: "com.google.Chrome")),
            reason: .shapeName
        )
    }

    func hint(_ text: String = "180 cm", processID: pid_t = 42) -> SelectionHint {
        SelectionHint(
            kind: .conversion, text: text,
            source: SelectionSource(text: "5 ft 11 in", application: FocusedApplication(processID: processID, bundleID: "com.apple.Safari"))
        )
    }

    @Test func showsTheHintWhereItWasToldTo() {
        chip.show(hint(), anchor: anchor)
        #expect(chip.hint == hint())
        #expect(log.shown.count == 1)
        #expect(log.shown[0].anchor == anchor)
    }

    @Test func goesAwayAfterFiveSeconds() {
        chip.show(hint(), anchor: anchor)
        scheduler.advance(by: .milliseconds(4_999))
        #expect(chip.hint != nil)
        #expect(log.hides == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        #expect(log.dismissals == 1)
    }

    @Test func hoveringKeepsItAsLongAsThePointerStaysOver() {
        chip.show(hint(), anchor: anchor)
        scheduler.advance(by: .seconds(1))
        chip.hoverChanged(true)
        scheduler.advance(by: .seconds(60))
        #expect(chip.hint != nil)
        #expect(log.hides == 0)
    }

    @Test func leavingStartsAShortWaitBeforeItGoes() {
        chip.show(hint(), anchor: anchor)
        chip.hoverChanged(true)
        scheduler.advance(by: .seconds(60))
        chip.hoverChanged(false)
        scheduler.advance(by: .milliseconds(1_999))
        #expect(chip.hint != nil)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil)
        #expect(log.dismissals == 1)
    }

    @Test func hoveringAfterTheFirstSecondsPausedTheClock() {
        chip.show(hint(), anchor: anchor)
        scheduler.advance(by: .seconds(4))
        chip.hoverChanged(true)
        scheduler.advance(by: .seconds(10))
        #expect(chip.hint != nil)
    }

    @Test func aNewHintReplacesTheOldOneAndRestartsTheClock() {
        chip.show(hint("180 cm"), anchor: anchor)
        scheduler.advance(by: .seconds(3))
        chip.show(hint("22,2 °C"), anchor: anchor)
        #expect(chip.hint?.text == "22,2 °C")
        #expect(log.shown.count == 2)
        // Replacing is not going away: nothing was hidden or reported in between.
        #expect(log.hides == 0)
        #expect(log.dismissals == 0)
        scheduler.advance(by: .seconds(4))
        #expect(chip.hint != nil)
        scheduler.advance(by: .seconds(1))
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        #expect(log.dismissals == 1)
    }

    @Test func aReplacementUnderThePointerStaysPut() {
        chip.show(hint("180 cm"), anchor: anchor)
        chip.hoverChanged(true)
        chip.show(hint("22,2 °C"), anchor: anchor)
        scheduler.advance(by: .seconds(60))
        #expect(chip.hint != nil)
    }

    @Test func dismissingHidesAtOnceAndStopsTheClock() {
        chip.show(hint(), anchor: anchor)
        chip.dismiss()
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        #expect(log.dismissals == 1)
        scheduler.advance(by: .seconds(10))
        #expect(log.hides == 1)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func dismissingNothingDoesNothing() {
        chip.dismiss()
        chip.hoverChanged(false)
        chip.hoverChanged(true)
        scheduler.advance(by: .seconds(10))
        #expect(log.hides == 0)
        #expect(log.dismissals == 0)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aPointerLeftOverFromAHiddenChipDoesNotKeepTheNextOne() {
        chip.show(hint(), anchor: anchor)
        chip.hoverChanged(true)
        chip.dismiss()
        chip.show(hint(), anchor: anchor)
        scheduler.advance(by: .seconds(5))
        #expect(chip.hint == nil)
    }

    @Test func anotherAppComingToTheFrontDismisses() {
        chip.show(hint(processID: 42), anchor: anchor)
        chip.applicationActivated(42)
        #expect(chip.hint != nil)
        chip.applicationActivated(99)
        #expect(chip.hint == nil)
        #expect(log.dismissals == 1)
    }

    @Test func anAppComingToTheFrontWithNoChipUpChangesNothing() {
        chip.applicationActivated(99)
        #expect(log.hides == 0)
        #expect(log.dismissals == 0)
    }

    // MARK: the small translate button

    @Test func theButtonIsDecidedAtOnceButOnlyShownAfterAShortDelay() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        #expect(chip.hint?.kind == .translateButton)
        scheduler.advance(by: .milliseconds(299))
        #expect(log.shown.isEmpty, "nothing flashes for a quick drag-and-copy")
        scheduler.advance(by: .milliseconds(1))
        #expect(log.shown.count == 1)
        #expect(log.shown[0].anchor == anchor)
    }

    @Test func theButtonStaysFourSecondsFromWhenItAppears() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(300))
        scheduler.advance(by: .milliseconds(3_999))
        #expect(chip.hint != nil)
        #expect(log.hides == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        #expect(log.dismissals == 1)
    }

    @Test func theTimesOfTheButtonAreItsOwnAndTheChipsAreUnchanged() {
        #expect(SelectionChip.buttonDelay == .milliseconds(300))
        #expect(SelectionChip.buttonLifetime == .seconds(4))
        #expect(SelectionChip.lifetime == .seconds(5))
    }

    @Test func dismissingDuringTheDelayMeansItIsNeverShown() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(100))
        chip.dismiss()
        #expect(chip.hint == nil)
        #expect(scheduler.pendingCount == 0, "neither the appearance nor the pointer's watch is left waiting")
        scheduler.advance(by: .seconds(10))
        #expect(log.shown.isEmpty)
    }

    @Test func anotherAppComingToTheFrontDuringTheDelayDismissesIt() {
        chip.show(button(processID: 42), anchor: anchor, watchesPointer: true)
        chip.applicationActivated(99)
        #expect(chip.hint == nil)
        scheduler.advance(by: .seconds(1))
        #expect(log.shown.isEmpty)
    }

    @Test func aNewHintDuringTheDelayTakesItsPlace() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(100))
        chip.show(hint("180 cm"), anchor: anchor)
        #expect(log.shown.map { $0.hint.kind } == [.conversion])
        scheduler.advance(by: .seconds(1))
        #expect(log.shown.count == 1, "the button that was waiting is gone")
    }

    @Test func aButtonAfterAChipWaitsAndThenReplacesIt() {
        chip.show(hint("180 cm"), anchor: anchor)
        // The chip's own clock is about to run out: it must not end what takes its place while that waits for its delay.
        scheduler.advance(by: .milliseconds(4_900))
        chip.show(button(), anchor: anchor, watchesPointer: true)
        #expect(log.hides == 1, "what was up goes at once, not after the button's delay")
        scheduler.advance(by: .milliseconds(300))
        #expect(log.shown.map { $0.hint.kind } == [.conversion, .translateButton])
        #expect(chip.hint?.kind == .translateButton)
        scheduler.advance(by: .milliseconds(3_999))
        #expect(chip.hint != nil)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil)
    }

    @Test func aPointerEventDuringTheDelayDoesNotHoldOrEndTheButton() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        // From the window that was there before, or one that is not up yet: there is nothing to hold.
        chip.hoverChanged(true)
        scheduler.advance(by: .milliseconds(300))
        scheduler.advance(by: .milliseconds(3_999))
        #expect(chip.hint != nil)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil, "it was not held by the stray event")
    }

    @Test func hoveringTheButtonKeepsItAndLeavingGivesTwoMoreSeconds() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(300))
        chip.hoverChanged(true)
        scheduler.advance(by: .seconds(60))
        #expect(chip.hint != nil)
        chip.hoverChanged(false)
        scheduler.advance(by: .milliseconds(1_999))
        #expect(chip.hint != nil)
        scheduler.advance(by: .milliseconds(1))
        #expect(chip.hint == nil)
    }

    // MARK: the pointer going far away

    @Test func thePointerGoingFarFromTheSelectionTakesTheButtonAway() {
        pointer.location = CGPoint(x: 40, y: 40)
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(300))
        pointer.location = CGPoint(x: 40 + 150, y: 40)
        scheduler.advance(by: .milliseconds(500))
        #expect(chip.hint != nil, "150 pt away is not yet far")
        pointer.location = CGPoint(x: 40 + 200, y: 40)
        scheduler.advance(by: SelectionChip.pointerPoll)
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func distanceIsFromTheSelectionNotFromWhereThePointerStarted() {
        // Inside the selection's rectangle is distance zero, however far from its centre.
        pointer.location = CGPoint(x: 11, y: 21)
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(300))
        pointer.location = CGPoint(x: 39, y: 59)
        scheduler.advance(by: .seconds(1))
        #expect(chip.hint != nil)
    }

    @Test func thePointerFlyingAwayDuringTheDelayMeansItIsNeverShown() {
        chip.show(button(), anchor: anchor, watchesPointer: true)
        pointer.location = CGPoint(x: 900, y: 900)
        scheduler.advance(by: .seconds(1))
        #expect(log.shown.isEmpty)
        #expect(chip.hint == nil)
    }

    @Test func aPointerThatIsAlreadyFarMeansTheButtonIsNeverShown() {
        // The mouse made the selection, then went elsewhere before the button could come up.
        pointer.location = CGPoint(x: 900, y: 900)
        chip.show(button(), anchor: anchor, watchesPointer: true)
        #expect(chip.hint == nil)
        scheduler.advance(by: .seconds(10))
        #expect(log.shown.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aPointerThatIsAlreadyFarAlsoTakesDownWhatWasUp() {
        chip.show(hint("180 cm"), anchor: anchor)
        pointer.location = CGPoint(x: 900, y: 900)
        chip.show(button(), anchor: anchor, watchesPointer: true)
        #expect(chip.hint == nil)
        #expect(log.hides == 1)
        scheduler.advance(by: .seconds(10))
        #expect(log.shown.count == 1)
    }

    @Test func aKeyboardSelectionsButtonComesUpWhateverTheDistanceOfThePointer() {
        pointer.location = CGPoint(x: 900, y: 900)
        chip.show(button(), anchor: anchor, watchesPointer: false)
        scheduler.advance(by: .milliseconds(300))
        #expect(log.shown.count == 1)
        pointer.location = CGPoint(x: 1_300, y: 100)
        scheduler.advance(by: .seconds(3))
        #expect(chip.hint != nil)
    }

    @Test func withoutWatchingThePointerItNeverEndsTheButton() {
        chip.show(button(), anchor: anchor, watchesPointer: false)
        scheduler.advance(by: .milliseconds(300))
        pointer.location = CGPoint(x: 5_000, y: 5_000)
        scheduler.advance(by: .seconds(3))
        #expect(chip.hint != nil)
    }

    @Test func aChipThatIsNotTheButtonIgnoresThePointer() {
        chip.show(hint("180 cm"), anchor: anchor, watchesPointer: true)
        pointer.location = CGPoint(x: 5_000, y: 5_000)
        scheduler.advance(by: .seconds(4))
        #expect(chip.hint != nil)
    }

    @Test func aChipWithNoPointerToAskNeverWatchesIt() {
        let log = ChipLog()
        let chip = SelectionChip(scheduler: scheduler, show: { log.show($0, $1) }, hide: { log.hide() }, onDismiss: { log.dismissal() })
        chip.show(button(), anchor: anchor, watchesPointer: true)
        scheduler.advance(by: .milliseconds(300))
        scheduler.advance(by: .seconds(3))
        #expect(chip.hint != nil)
    }
}
