import CoreGraphics
import Foundation
import Testing
@testable import WindowLayoutModule

/// Telling a window being dragged from any other drag, with a fake window and fake Accessibility: nothing real moves.
@Suite struct WindowDragDetectorTests {
    let window = FakeWindow()
    let probe: FakeWindowProbe
    let state = TrustBox()
    let detector: WindowDragDetector

    final class TrustBox {
        var isTrusted = true
    }

    init() {
        let probe = FakeWindowProbe(window)
        let state = state
        self.probe = probe
        detector = WindowDragDetector(probe: probe, isTrusted: { state.isTrusted })
    }

    /// Drags in steps `interval` apart, moving the window with each unless told not to.
    func drag(steps: Int, from time: TimeInterval = 0, interval: TimeInterval = 0.05, moving: Bool = true) -> [Bool] {
        (0..<steps).map { step in
            if moving { window.drag(to: CGPoint(x: 100 + 10 * CGFloat(step + 1), y: 100)) }
            return detector.mouseDragged(at: time + interval * TimeInterval(step))
        }
    }

    @Test func aWindowThatFollowsThePointerIsRecognisedOnceAndOnlyOnce() {
        detector.mouseDown()
        // The first look is the baseline, the second sees the window has moved.
        #expect(drag(steps: 5) == [false, true, false, false, false])
        #expect(detector.isDragging)
        #expect(detector.window === window)
    }

    @Test func afterTheRecognitionTheWindowIsNotAskedAboutAgain() {
        detector.mouseDown()
        _ = drag(steps: 2)
        let asked = probe.asked
        _ = drag(steps: 6, from: 1)
        #expect(probe.asked == asked)
    }

    @Test func aDragThatMovesNoWindowIsGivenUpAfterAFewLooks() {
        // Selecting text, dragging a slider or a file: the window under it stays where it is.
        detector.mouseDown()
        #expect(drag(steps: 20, moving: false).allSatisfy { !$0 })
        #expect(probe.asked == WindowDragDetector.maxSamples)
        #expect(!detector.isDragging)
        // Even a window that starts to move now is not taken for a window drag: the drag is something else.
        #expect(drag(steps: 3, from: 2).allSatisfy { !$0 })
        #expect(probe.asked == WindowDragDetector.maxSamples)
    }

    @Test func resizingAWindowFromItsEdgeIsNotMovingIt() {
        detector.mouseDown()
        // Dragging the top left corner moves the origin and changes the size together.
        var results: [Bool] = []
        for step in 0..<4 {
            let delta = CGFloat(step + 1) * 10
            window.current = CGRect(x: 100 - delta, y: 100 - delta, width: 800 + delta, height: 600 + delta)
            results.append(detector.mouseDragged(at: 0.05 * TimeInterval(step)))
        }
        #expect(results == [false, false, false, false])
        #expect(!detector.isDragging)
    }

    @Test func aWindowThatJitterBelowAPointIsNotMoving() {
        detector.mouseDown()
        for step in 0..<4 {
            window.current = CGRect(x: 100 + (step.isMultiple(of: 2) ? 0.2 : 0), y: 100, width: 800, height: 600)
            #expect(!detector.mouseDragged(at: 0.05 * TimeInterval(step)))
        }
    }

    @Test func lookingIsLimitedToOncePerSampleInterval() {
        detector.mouseDown()
        window.drag(to: CGPoint(x: 110, y: 100))
        #expect(!detector.mouseDragged(at: 1.000))
        // Ten events in the next 20 ms: no looks, so no recognition either.
        for tick in 1...10 {
            window.drag(to: CGPoint(x: 110 + CGFloat(tick) * 10, y: 100))
            #expect(!detector.mouseDragged(at: 1.000 + 0.002 * TimeInterval(tick)))
        }
        #expect(probe.asked == 1)
        window.drag(to: CGPoint(x: 400, y: 100))
        #expect(detector.mouseDragged(at: 1.000 + WindowDragDetector.sampleInterval))
        #expect(probe.asked == 2)
    }

    @Test func aDifferentWindowTakesOverTheBaseline() {
        // The click activated another app: the first window in focus is the old app's, which does not move.
        let old = FakeWindow()
        probe.focused = old
        detector.mouseDown()
        #expect(!detector.mouseDragged(at: 0))
        probe.focused = window
        window.drag(to: CGPoint(x: 120, y: 100))
        // First sight of this window: a baseline, not a drag.
        #expect(!detector.mouseDragged(at: 0.05))
        window.drag(to: CGPoint(x: 140, y: 100))
        #expect(detector.mouseDragged(at: 0.10))
        #expect(detector.window === window)
    }

    @Test func noFocusedWindowTwiceInARowGivesUp() {
        probe.focused = nil
        detector.mouseDown()
        #expect(!detector.mouseDragged(at: 0))
        #expect(!detector.mouseDragged(at: 0.05))
        // A window now would be too late: the app did not answer, and asking again would block again.
        probe.focused = window
        #expect(drag(steps: 4, from: 1).allSatisfy { !$0 })
        #expect(probe.asked == WindowDragDetector.maxMisses)
    }

    @Test func aWindowWhoseFrameCannotBeReadCountsAsNoWindow() {
        window.current = nil
        detector.mouseDown()
        #expect(!detector.mouseDragged(at: 0))
        #expect(!detector.mouseDragged(at: 0.05))
        #expect(probe.asked == WindowDragDetector.maxMisses)
    }

    @Test func withoutAccessibilityNothingIsEverAskedOrRecognised() {
        state.isTrusted = false
        detector.mouseDown()
        #expect(drag(steps: 5).allSatisfy { !$0 })
        #expect(probe.asked == 0)
    }

    @Test func trustIsCheckedAtEveryMouseDownSoAGrantTakesEffectAtOnce() {
        state.isTrusted = false
        detector.mouseDown()
        #expect(drag(steps: 3).allSatisfy { !$0 })
        detector.end()
        state.isTrusted = true
        detector.mouseDown()
        #expect(drag(steps: 3, from: 5) == [false, true, false])
    }

    @Test func dragsWithoutAMouseDownAreIgnored() {
        #expect(drag(steps: 4).allSatisfy { !$0 })
        #expect(probe.asked == 0)
    }

    @Test func endingForgetsTheWindowAndTheNextPressStartsOver() {
        detector.mouseDown()
        _ = drag(steps: 2)
        #expect(detector.isDragging)
        detector.end()
        #expect(!detector.isDragging && detector.window == nil)
        #expect(drag(steps: 3, from: 3).allSatisfy { !$0 }, "no press, no drag")
        detector.mouseDown()
        // The window has not changed since the last press, so the next two looks are baseline and movement again.
        #expect(drag(steps: 3, from: 4) == [false, true, false])
    }

    @Test func aNewPressDuringADragStartsOver() {
        detector.mouseDown()
        _ = drag(steps: 2)
        detector.mouseDown()
        #expect(!detector.isDragging)
    }
}
