import AppKit
import MyNotchCore
import Testing
@testable import NotchUI

/// The recognizer as a state machine fed with what a trackpad sends: a finger phase per event (`began`, `changed`,
/// `ended`), then momentum events with no finger phase, and a mouse wheel with neither.
@Suite struct TabSwipeTests {
    typealias Step = TabSwipeRecognizer.Step

    /// One recognizer fed event by event, like the notch feeds it.
    final class Trackpad {
        var recognizer = TabSwipeRecognizer()

        /// Feeds one event and returns what it produced.
        func feed(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0, momentum: NSEvent.Phase = []) -> Step? {
            recognizer.feed(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy)
        }

        /// A gesture's events from `began` through `ended`; the steps it produced, in order.
        func gesture(_ moves: [(dx: CGFloat, dy: CGFloat)]) -> [Step] {
            var steps: [Step] = []
            steps += feed(.began).map { [$0] } ?? []
            for move in moves { steps += feed(.changed, move.dx, move.dy).map { [$0] } ?? [] }
            steps += feed(.ended).map { [$0] } ?? []
            return steps
        }
    }

    @Test func aSwipeLeftGoesToTheNextTabOnceItHasTravelledFarEnough() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, -10) == nil)
        #expect(pad.feed(.changed, -15) == nil)
        #expect(pad.feed(.changed, -20) == .next)
    }

    @Test func aSwipeRightGoesToThePreviousTab() {
        let pad = Trackpad()
        #expect(pad.gesture([(15, 0), (15, 0), (15, 0)]) == [.previous])
    }

    @Test func aShortSwipeDoesNothing() {
        let pad = Trackpad()
        #expect(pad.gesture([(10, 0), (10, 0), (10, 0)]).isEmpty)
    }

    @Test func aGestureStepsOnlyOnceHoweverFarItGoes() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (30, 0), count: 20)) == [.previous])
    }

    @Test func momentumAfterTheFingersLiftNeverStepsAgain() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, -50) == .next)
        #expect(pad.feed(.ended) == nil)
        #expect(pad.feed([], -80, momentum: .began) == nil)
        for _ in 0..<10 { #expect(pad.feed([], -80, momentum: .changed) == nil) }
        #expect(pad.feed([], 0, momentum: .ended) == nil)
    }

    @Test func momentumAloneNeverStepsEvenAfterAShortGesture() {
        let pad = Trackpad()
        #expect(pad.gesture([(10, 0), (10, 0)]).isEmpty)
        #expect(pad.feed([], -200, momentum: .began) == nil)
        #expect(pad.feed([], -200, momentum: .changed) == nil)
    }

    @Test func aStepDuringMomentumFlaggedEventsIsIgnoredEvenWithAFingerPhase() {
        let pad = Trackpad()
        // Both phases never arrive together from a trackpad; if they did, the momentum flag wins.
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, -100, momentum: .changed) == nil)
    }

    @Test func aVerticalGestureNeverSteps() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (2, 30), count: 20)).isEmpty)
    }

    @Test func aGestureThatStartsVerticalStaysIgnoredEvenIfItTurnsHorizontal() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 20) == nil)
        for _ in 0..<10 { #expect(pad.feed(.changed, -60, 0) == nil) }
    }

    @Test func aDiagonalGestureIsIgnored() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (20, 20), count: 10)).isEmpty)
        #expect(pad.gesture(Array(repeating: (30, 20), count: 10)).isEmpty)
    }

    @Test func aClearlyHorizontalGestureWithALittleDriftStillSteps() {
        let pad = Trackpad()
        #expect(pad.gesture([(30, 8), (30, 8)]) == [.previous])
        #expect(pad.gesture([(-30, -10), (-30, -10)]) == [.next])
    }

    @Test func aNewGestureStartsFromZeroAndCanStepAgain() {
        let pad = Trackpad()
        #expect(pad.gesture([(-30, 0)]).isEmpty)
        // Not 30 + 30: the first gesture's travel is forgotten.
        #expect(pad.gesture([(-30, 0)]).isEmpty)
        #expect(pad.gesture([(-60, 0)]) == [.next])
        #expect(pad.gesture([(60, 0)]) == [.previous])
        #expect(pad.gesture([(-60, 0)]) == [.next])
    }

    @Test func aGestureWithoutABeginIsIgnored() {
        let pad = Trackpad()
        // Started somewhere else (a view that used it) and ended up here.
        for _ in 0..<5 { #expect(pad.feed(.changed, -60, 0) == nil) }
        #expect(pad.feed(.ended) == nil)
    }

    @Test func aCancelledGestureStopsCounting() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, -30) == nil)
        #expect(pad.feed(.cancelled) == nil)
        #expect(pad.feed(.changed, -60) == nil)
    }

    @Test func aMouseWheelNeverSteps() {
        let pad = Trackpad()
        for _ in 0..<10 { #expect(pad.feed([], -100, 0) == nil) }
    }

    @Test func theTouchesOfAGestureThatHasNotStartedMovingDoNothing() {
        let pad = Trackpad()
        #expect(pad.feed(.mayBegin) == nil)
        #expect(pad.feed(.stationary) == nil)
        #expect(pad.feed(.began, -60, 0) == .next)
    }

    @Test func aBeginEventThatAlreadyCarriesMovementCounts() {
        let pad = Trackpad()
        #expect(pad.feed(.began, 50, 0) == .previous)
    }

    @Test func goingBackAndForthCountsTheNetDistance() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, -30) == nil)
        #expect(pad.feed(.changed, 50) == nil)
        #expect(pad.feed(.changed, 30) == .previous)
    }
}

@Suite struct TabSwipeTargetTests {
    let tabs: [ModuleID] = ["a", "b", "c"]

    func target(_ step: TabSwipeRecognizer.Step, state: NotchState, enabled: Bool = true, systemAllows: Bool = true) -> ModuleID? {
        step.target(state: state, tabs: tabs, enabled: enabled, systemAllows: systemAllows)
    }

    @Test func nextAndPreviousAreTheNeighboursInTheTabBar() {
        #expect(target(.next, state: .open("a")) == "b")
        #expect(target(.next, state: .open("b")) == "c")
        #expect(target(.previous, state: .open("c")) == "b")
        #expect(target(.previous, state: .open("b")) == "a")
    }

    @Test func thereIsNothingBeyondTheEnds() {
        #expect(target(.previous, state: .open("a")) == nil)
        #expect(target(.next, state: .open("c")) == nil)
    }

    @Test func onlyAnOpenNotchOnAKnownTabSwipes() {
        for state in [NotchState.closed, .compact, .toast, .open(nil), .open("gone")] {
            #expect(target(.next, state: state) == nil, "\(state)")
            #expect(target(.previous, state: state) == nil, "\(state)")
        }
    }

    @Test func theSettingAndTheSystemBothHaveToAllowIt() {
        #expect(target(.next, state: .open("a"), enabled: false) == nil)
        #expect(target(.next, state: .open("a"), systemAllows: false) == nil)
        #expect(target(.next, state: .open("a"), enabled: false, systemAllows: false) == nil)
    }

    @Test func aSingleTabHasNowhereToGo() {
        #expect(TabSwipeRecognizer.Step.next.target(state: .open("a"), tabs: ["a"], enabled: true, systemAllows: true) == nil)
    }

    @Test func swipingIsOnByDefault() {
        #expect(InterfaceSettings.swipeBetweenTabs.defaultValue == true)
    }
}
