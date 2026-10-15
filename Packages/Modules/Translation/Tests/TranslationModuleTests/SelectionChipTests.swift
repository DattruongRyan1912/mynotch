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

/// How long a chip lives and what keeps it or ends it, on a clock the test moves.
@Suite struct SelectionChipTests {
    let scheduler = ManualScheduler()
    let log = ChipLog()
    let chip: SelectionChip
    let anchor = CGRect(x: 10, y: 20, width: 30, height: 40)

    init() {
        let (scheduler, log) = (scheduler, log)
        chip = SelectionChip(
            scheduler: scheduler, show: { log.show($0, $1) }, hide: { log.hide() }, onDismiss: { log.dismissal() }
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
}
