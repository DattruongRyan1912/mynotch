import AppKit
import Foundation
import Testing
@testable import TimerModule

/// What decides whether a scroll over the dial turns it or goes on to the notch (which swipes between tabs with it).
@Suite struct DialScrollGateTests {
    func feed(_ gate: inout DialScrollGate, _ phase: NSEvent.Phase, dx: Double = 0, dy: Double = 0, momentum: NSEvent.Phase = []) -> DialScrollGate.Action {
        gate.feed(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy, isPrecise: true)
    }

    @Test func anUpAndDownGestureTurnsTheDialAndNothingElseSeesIt() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dy: 40) == .minutes(3))   // 40 points at 12 per minute
        #expect(feed(&gate, .changed, dy: 24) == .minutes(2))
        #expect(feed(&gate, .changed, dy: 2) == .consume)
        #expect(feed(&gate, .ended) == .consume)
    }

    @Test func aSidewaysGestureIsLeftToTheNotchFromFirstToLast() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dx: 40) == .forward)
        #expect(feed(&gate, .changed, dx: 40, dy: 2) == .forward)
        #expect(feed(&gate, .ended) == .forward)
    }

    @Test func aGestureThatStartedSidewaysStaysSidewaysWhateverItDoesNext() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dx: 30) == .forward)
        #expect(feed(&gate, .changed, dy: 80) == .forward)
    }

    @Test func aGestureThatStartedUpAndDownStaysWithTheDial() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dy: 30) == .minutes(2))
        #expect(feed(&gate, .changed, dx: 100) == .consume)
    }

    @Test func untilTheDirectionIsClearEventsGoOnAndTheTravelCountsOnceItIs() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dx: 2, dy: 3) == .forward)
        // 3 + 9 = 12 points up and down, 2 sideways: the dial's, and the first 3 points are not lost.
        #expect(feed(&gate, .changed, dy: 9) == .minutes(1))
    }

    @Test func aDiagonalDragBelongsToNobody() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dx: 30, dy: 20) == .forward)
        #expect(feed(&gate, .changed, dx: 30, dy: 20) == .forward)
    }

    @Test func momentumNeverTurnsTheDialAndGoesOn() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dy: 40) == .minutes(3))
        #expect(feed(&gate, .ended) == .consume)
        #expect(feed(&gate, [], dy: 40, momentum: .began) == .forward)
        #expect(feed(&gate, [], dy: 40, momentum: .changed) == .forward)
        #expect(feed(&gate, [], dy: 40, momentum: .ended) == .forward)
    }

    @Test func aNewGestureStartsFromNothing() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .began, dy: 40) == .minutes(3))   // 4 twelfths are carried
        #expect(feed(&gate, .ended) == .consume)
        // 8 points is two thirds of a minute; with the old carry it would be a whole one.
        #expect(feed(&gate, .began, dy: 8) == .consume)
    }

    @Test func aGestureThatNeverBeganHereIsNotTheDials() {
        var gate = DialScrollGate()
        #expect(feed(&gate, .changed, dy: 40) == .forward)
        #expect(feed(&gate, .mayBegin) == .forward)
        #expect(feed(&gate, .ended) == .forward)
    }

    @Test func aWheelNotchGoesUpAndDownOnlyWhenItIsUpAndDown() {
        var gate = DialScrollGate()
        #expect(gate.feed(phase: [], momentumPhase: [], deltaX: 0, deltaY: 3, isPrecise: false) == .minutes(3))
        #expect(gate.feed(phase: [], momentumPhase: [], deltaX: 0, deltaY: -2, isPrecise: false) == .minutes(-2))
        #expect(gate.feed(phase: [], momentumPhase: [], deltaX: 3, deltaY: 0, isPrecise: false) == .forward)
        #expect(gate.feed(phase: [], momentumPhase: [], deltaX: 5, deltaY: 3, isPrecise: false) == .forward)
    }
}

/// The catcher in a view hierarchy: events are made here and handed to it, as `ScrollRoutingTests` in NotchUI does for
/// the hosting view; nothing is posted to the system.
@Suite struct ScrollWheelCatcherTests {
    final class Parent: NSView {
        private(set) var seen = 0
        override func scrollWheel(with event: NSEvent) { seen += 1 }
    }

    func fixture() -> (parent: Parent, catcher: ScrollWheelCatcher.CatcherView, received: () -> [Int]) {
        let parent = Parent(frame: CGRect(x: 0, y: 0, width: 112, height: 112))
        let catcher = ScrollWheelCatcher.CatcherView(frame: parent.bounds)
        parent.addSubview(catcher)
        var received: [Int] = []
        catcher.onScroll = { received.append($0) }
        return (parent, catcher, { received })
    }

    func event(dx: Int32 = 0, dy: Int32 = 0, phase: CGScrollPhase? = nil, momentum: CGMomentumScrollPhase? = nil) throws -> NSEvent {
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let phase { cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
        if let momentum { cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue)) }
        return try #require(NSEvent(cgEvent: cgEvent))
    }

    @Test func aSidewaysSwipeOverTheDialGoesUpToTheNotch() throws {
        let (parent, catcher, received) = fixture()
        catcher.scrollWheel(with: try event(dx: -40, phase: .began))
        catcher.scrollWheel(with: try event(dx: -40, phase: .changed))
        #expect(parent.seen == 2)
        #expect(received().isEmpty)
    }

    @Test func anUpAndDownScrollOverTheDialTurnsItAndStopsThere() throws {
        let (parent, catcher, received) = fixture()
        catcher.scrollWheel(with: try event(dy: 40, phase: .began))
        catcher.scrollWheel(with: try event(dy: 40, phase: .changed))
        #expect(parent.seen == 0)
        #expect(received().count == 2)
        #expect(received().allSatisfy { $0 != 0 })
        #expect(Set(received().map { $0.signum() }).count == 1)
    }

    @Test func theScrollingAfterTheFingersLiftDoesNotTurnTheDial() throws {
        let (parent, catcher, received) = fixture()
        catcher.scrollWheel(with: try event(dy: 40, phase: .began))
        catcher.scrollWheel(with: try event(dy: 0, phase: .ended))
        let before = received().count
        catcher.scrollWheel(with: try event(dy: 40, momentum: .begin))
        catcher.scrollWheel(with: try event(dy: 40, momentum: .continuous))
        #expect(received().count == before)
        #expect(parent.seen == 2)
    }

    @Test func aClickOrDragFallsThroughToTheDialBeneath() {
        let (_, catcher, _) = fixture()
        #expect(catcher.hitTest(CGPoint(x: 56, y: 56)) == nil)
    }
}
