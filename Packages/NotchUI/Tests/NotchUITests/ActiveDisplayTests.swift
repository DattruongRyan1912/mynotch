import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

/// The display "Màn hình đang dùng" shows the notch on: it follows the pointer, but only once the pointer has stayed on
/// another display for a moment. Time is a `ManualScheduler`, so nothing here waits.
@Suite struct ActiveDisplayTests {
    final class Changes {
        var count = 0
    }

    struct Fixture {
        let scheduler = ManualScheduler()
        let changes = Changes()
        let active: ActiveDisplay

        /// Two displays with the pointer on the first, as the app is at launch.
        init(displays: [CGDirectDisplayID] = [1, 2], pointerOn: CGDirectDisplayID? = 1) {
            let changes = changes
            active = ActiveDisplay(scheduler: scheduler, onChange: { changes.count += 1 })
            active.displaysChanged(displays, pointerOn: pointerOn)
            changes.count = 0
        }
    }

    @Test func theSettleDelayIsAboutAThirdOfASecond() {
        #expect(ActiveDisplay.settleDelay == .milliseconds(300))
    }

    // MARK: start and displays coming and going

    @Test func startsOnTheDisplayThePointerIsOnWithoutWaiting() {
        let scheduler = ManualScheduler()
        let active = ActiveDisplay(scheduler: scheduler, onChange: {})
        #expect(active.current == nil)
        active.displaysChanged([1, 2], pointerOn: 2)
        #expect(active.current == 2)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func startsOnTheMainDisplayWhenTheBetweenDisplaysPointerIsNowhere() {
        let active = ActiveDisplay(scheduler: ManualScheduler(), onChange: {})
        active.displaysChanged([4, 5], pointerOn: nil)
        #expect(active.current == 4)
    }

    @Test func aChangeOfTheDisplayListMovesToThePointerAtOnceAndAnUnchangedListDoesNothing() {
        let fixture = Fixture()
        // Same displays, e.g. a settings change or a wake: nothing moves, even though the pointer is elsewhere.
        fixture.active.displaysChanged([2, 1], pointerOn: 2)
        #expect(fixture.active.current == 1)
        #expect(fixture.changes.count == 0)
        // A display plugged in: the pointer decides, without the delay.
        fixture.active.displaysChanged([1, 2, 3], pointerOn: 3)
        #expect(fixture.active.current == 3)
        #expect(fixture.changes.count == 1)
    }

    @Test func unpluggingTheActiveDisplayMovesToTheDisplayThePointerIsOnNow() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        fixture.scheduler.advance(by: ActiveDisplay.settleDelay)
        #expect(fixture.active.current == 2)
        fixture.changes.count = 0
        fixture.active.displaysChanged([1], pointerOn: 1)
        #expect(fixture.active.current == 1)
        #expect(fixture.changes.count == 1)
        // Plugged in again with the pointer still on the laptop: the notch does not jump back to the old display.
        fixture.active.displaysChanged([1, 2], pointerOn: 1)
        #expect(fixture.active.current == 1)
    }

    @Test func aChangeOfDisplaysDropsAMoveThatWasWaiting() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        #expect(fixture.scheduler.pendingCount == 1)
        fixture.active.displaysChanged([1], pointerOn: 1)
        #expect(fixture.scheduler.pendingCount == 0)
        fixture.scheduler.advance(by: .seconds(1))
        #expect(fixture.active.current == 1)
    }

    // MARK: following the pointer

    @Test func moveToAnotherDisplayHappensOnlyAfterThePointerStayedThere() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        fixture.scheduler.advance(by: .milliseconds(299))
        #expect(fixture.active.current == 1)
        #expect(fixture.changes.count == 0)
        fixture.scheduler.advance(by: .milliseconds(1))
        #expect(fixture.active.current == 2)
        #expect(fixture.changes.count == 1)
    }

    @Test func passingThroughAnotherDisplayAndBackNeverMovesTheNotch() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        fixture.scheduler.advance(by: .milliseconds(200))
        fixture.active.pointerMoved(onto: 1)
        fixture.scheduler.advance(by: .seconds(2))
        #expect(fixture.active.current == 1)
        #expect(fixture.changes.count == 0)
        #expect(fixture.scheduler.pendingCount == 0)
    }

    @Test func aPointerThatKeepsCrossingBetweenDisplaysNeverMakesTheNotchFlicker() {
        let fixture = Fixture()
        for step in 0..<40 {
            fixture.active.pointerMoved(onto: step.isMultiple(of: 2) ? 2 : 1)
            fixture.scheduler.advance(by: .milliseconds(100))
        }
        #expect(fixture.changes.count == 0)
        #expect(fixture.active.current == 1)
    }

    @Test func movingAroundOnTheNewDisplayDoesNotRestartTheWait() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        for _ in 0..<9 {
            fixture.scheduler.advance(by: .milliseconds(30))
            fixture.active.pointerMoved(onto: 2)
        }
        // 270 ms in: still waiting; the 300 ms count from the first move, not the last.
        #expect(fixture.active.current == 1)
        fixture.scheduler.advance(by: .milliseconds(30))
        #expect(fixture.active.current == 2)
        #expect(fixture.changes.count == 1)
    }

    @Test func goingOnToAThirdDisplayRestartsTheWaitForThatOne() {
        let fixture = Fixture(displays: [1, 2, 3])
        fixture.active.pointerMoved(onto: 2)
        fixture.scheduler.advance(by: .milliseconds(200))
        fixture.active.pointerMoved(onto: 3)
        fixture.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.active.current == 1)
        fixture.scheduler.advance(by: .milliseconds(100))
        #expect(fixture.active.current == 3)
        #expect(fixture.changes.count == 1)
    }

    @Test func aPointerBetweenDisplaysChangesNothingAndLeavesTheWaitRunning() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: nil)
        #expect(fixture.scheduler.pendingCount == 0)
        fixture.active.pointerMoved(onto: 2)
        fixture.active.pointerMoved(onto: nil)
        fixture.scheduler.advance(by: ActiveDisplay.settleDelay)
        #expect(fixture.active.current == 2)
    }

    @Test func staysOnTheDisplayItIsOnWhenThePointerMovesAroundThere() {
        let fixture = Fixture()
        for _ in 0..<50 { fixture.active.pointerMoved(onto: 1) }
        #expect(fixture.scheduler.pendingCount == 0)
        #expect(fixture.changes.count == 0)
    }

    @Test func goingBackAfterASettledMoveWaitsAgainAndStoppingDropsTheWait() {
        let fixture = Fixture()
        fixture.active.pointerMoved(onto: 2)
        fixture.scheduler.advance(by: ActiveDisplay.settleDelay)
        fixture.active.pointerMoved(onto: 1)
        #expect(fixture.active.current == 2)
        fixture.active.stop()
        fixture.scheduler.advance(by: .seconds(1))
        #expect(fixture.active.current == 2)
        #expect(fixture.changes.count == 1)
    }

    @Test func theModeThenShowsTheNotchOnTheSettledDisplayOnly() {
        let fixture = Fixture()
        func shown() -> Set<CGDirectDisplayID> {
            DisplaySelection.shown(mode: .cursor, displays: [1, 2], active: fixture.active.current)
        }
        #expect(shown() == [1])
        fixture.active.pointerMoved(onto: 2)
        #expect(shown() == [1])
        fixture.scheduler.advance(by: ActiveDisplay.settleDelay)
        #expect(shown() == [2])
    }
}
