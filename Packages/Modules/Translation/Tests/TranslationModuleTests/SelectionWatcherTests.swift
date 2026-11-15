import CoreGraphics
import MyNotchTestSupport
import Testing
@testable import TranslationModule

/// What the watcher asked for, in order.
final class WatcherLog {
    private(set) var selections: [CGPoint] = []
    /// For each read, whether the pointer made the selection (a mouse gesture) rather than the keyboard.
    private(set) var byPointer: [Bool] = []
    /// For each dismissal, whether the selection itself is gone (a click or a key) rather than only maybe changing (a press).
    private(set) var dismissals: [Bool] = []

    func selection(at point: CGPoint, byPointer: Bool) {
        selections.append(point)
        self.byPointer.append(byPointer)
    }

    func dismissal(forgetting: Bool) { dismissals.append(forgetting) }
}

/// The state machine over fake input: nothing here posts or reads a real event.
@Suite struct SelectionWatcherTests {
    let scheduler = ManualScheduler()
    let log = WatcherLog()
    let watcher: SelectionWatcher

    init() {
        let (scheduler, log) = (scheduler, log)
        watcher = SelectionWatcher(
            scheduler: scheduler, onSelection: { log.selection(at: $0, byPointer: $1) }, onDismiss: { log.dismissal(forgetting: $0) }
        )
    }

    func drag(from start: CGPoint, to end: CGPoint) {
        watcher.handle(.mouseDown(start))
        watcher.handle(.mouseUp(end, clicks: 1))
    }

    func key(_ code: UInt16, shift: Bool = false, command: Bool = false, at pointer: CGPoint = CGPoint(x: 5, y: 6)) {
        watcher.handle(.keyUp(KeyPress(code: code, shift: shift, command: command), pointer: pointer))
    }

    @Test func aDragReadsOnceTheDebounceHasPassed() {
        drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 12))
        #expect(log.selections.isEmpty)
        scheduler.advance(by: .milliseconds(249))
        #expect(log.selections.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(log.selections == [CGPoint(x: 200, y: 12)])
    }

    @Test func aDoubleClickReadsAtTheSecondRelease() {
        watcher.handle(.mouseDown(CGPoint(x: 50, y: 50)))
        watcher.handle(.mouseUp(CGPoint(x: 50, y: 50), clicks: 1))
        #expect(scheduler.pendingCount == 0)
        watcher.handle(.mouseDown(CGPoint(x: 50, y: 50)))
        watcher.handle(.mouseUp(CGPoint(x: 50, y: 50), clicks: 2))
        scheduler.advance(by: .milliseconds(250))
        #expect(log.selections == [CGPoint(x: 50, y: 50)])
    }

    @Test func aTripleClickReads() {
        watcher.handle(.mouseDown(CGPoint(x: 50, y: 50)))
        watcher.handle(.mouseUp(CGPoint(x: 50, y: 50), clicks: 3))
        scheduler.advance(by: .milliseconds(250))
        #expect(log.selections.count == 1)
    }

    @Test func aPlainClickReadsNothing() {
        drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50))
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(2))
        #expect(log.selections.isEmpty)
    }

    @Test func aReleaseWithNoPressBeforeItIsNotKnownToBeADrag() {
        watcher.handle(.mouseUp(CGPoint(x: 500, y: 500), clicks: 1))
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
    }

    @Test func aSlipOfAFewPointsIsStillAClick() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3, y: 0))
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 4))
        scheduler.advance(by: .seconds(1))
        #expect(log.selections == [CGPoint(x: 0, y: 4)])
    }

    @Test(arguments: [UInt16(123), 124, 125, 126, 115, 119, 116, 121])
    func shiftWithAMovingKeyReadsAtThePointer(code: UInt16) {
        key(code, shift: true, at: CGPoint(x: 70, y: 80))
        scheduler.advance(by: .milliseconds(250))
        #expect(log.selections == [CGPoint(x: 70, y: 80)])
        #expect(log.dismissals.isEmpty)
    }

    @Test func shiftAndCommandWithAnArrowReads() {
        key(124, shift: true, command: true)
        scheduler.advance(by: .milliseconds(250))
        #expect(log.selections.count == 1)
    }

    @Test func commandAReads() {
        key(0, command: true)
        scheduler.advance(by: .milliseconds(250))
        #expect(log.selections.count == 1)
        #expect(log.dismissals.isEmpty)
    }

    @Test func otherKeysReadNothingAndSayTheSelectionMayBeGone() {
        key(0)                               // a typed "a"
        key(0, shift: true, command: true)   // ⇧⌘A is not select all
        key(124)                             // an arrow that moves the caret instead
        key(53)                              // Esc
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
        #expect(log.dismissals == [true, true, true, true])
    }

    @Test func twoGesturesInQuickSuccessionReadOnceAtTheLastOne() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        scheduler.advance(by: .milliseconds(100))
        key(124, shift: true, at: CGPoint(x: 300, y: 300))
        scheduler.advance(by: .milliseconds(249))
        #expect(log.selections.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(log.selections == [CGPoint(x: 300, y: 300)])
        scheduler.advance(by: .seconds(5))
        #expect(log.selections.count == 1)
    }

    @Test func aNewPressBeforeTheReadMeansTheSelectionIsChangingAgain() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        scheduler.advance(by: .milliseconds(100))
        watcher.handle(.mouseDown(CGPoint(x: 100, y: 0)))
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
    }

    @Test func everyPressSaysTheSelectionMayBeGone() {
        watcher.handle(.mouseDown(CGPoint(x: 1, y: 1)))
        watcher.handle(.mouseDown(CGPoint(x: 2, y: 2)))
        #expect(log.dismissals == [false, false])
    }

    @Test func aReleaseDismissesNothing() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(log.dismissals == [false])   // only the press
    }

    @Test func stoppingDropsTheReadInWaitAndIgnoresLaterInput() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        watcher.stop()
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        key(124, shift: true)
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
        #expect(log.dismissals == [false])
    }

    @Test func theReadSaysWhetherThePointerMadeTheSelection() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        scheduler.advance(by: .milliseconds(250))
        key(124, shift: true, at: CGPoint(x: 300, y: 300))
        scheduler.advance(by: .milliseconds(250))
        watcher.handle(.mouseDown(CGPoint(x: 5, y: 5)))
        watcher.handle(.mouseUp(CGPoint(x: 5, y: 5), clicks: 2))
        scheduler.advance(by: .milliseconds(250))
        #expect(log.byPointer == [true, false, true])
    }

    @Test func aPlainClickSaysTheSelectionIsGone() {
        drag(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 51, y: 50))
        // The press only says it may be changing; the release that selected nothing says it has.
        #expect(log.dismissals == [false, true])
    }

    @Test func aDragOrAMultiClickDoesNotSayTheSelectionIsGone() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        watcher.handle(.mouseDown(CGPoint(x: 5, y: 5)))
        watcher.handle(.mouseUp(CGPoint(x: 5, y: 5), clicks: 2))
        #expect(log.dismissals == [false, false])
    }

    @Test func aDoubleClickStartsWithAPlainClickWhichForgetsTheOldSelection() {
        watcher.handle(.mouseDown(CGPoint(x: 5, y: 5)))
        watcher.handle(.mouseUp(CGPoint(x: 5, y: 5), clicks: 1))
        #expect(log.dismissals == [false, true])
    }

    @Test func copyingLeavesTheSelectionAndAPendingReadAlone() {
        drag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        scheduler.advance(by: .milliseconds(100))
        key(8, command: true)   // ⌘C
        scheduler.advance(by: .milliseconds(150))
        #expect(log.selections == [CGPoint(x: 100, y: 0)])
        #expect(log.dismissals == [false])   // only the press
        // Another command key is not a copy.
        key(7, command: true)   // ⌘X
        #expect(log.dismissals == [false, true])
    }

    @Test func switchingAppsIsNotTheWatchersBusiness() {
        watcher.handle(.applicationActivated(123))
        scheduler.advance(by: .seconds(1))
        #expect(log.selections.isEmpty)
        #expect(log.dismissals.isEmpty)
    }
}
